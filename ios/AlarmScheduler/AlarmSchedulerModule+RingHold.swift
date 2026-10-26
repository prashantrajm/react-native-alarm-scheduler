import Foundation

#if canImport(AlarmKit)
import AlarmKit
#endif

/// On iOS the app's own audio is the main ring and AlarmKit is the backstop, so a hold adds no
/// audio work here: it re-arms the alarm's one deterministic backup timer `seconds` out. If the app
/// stops renewing, is killed or reloads, the backup rings.
extension AlarmSchedulerModule {
  func holdRing(alarmId: String, seconds: Double?) async -> [String: Any] {
    let notHeld: [String: Any] = ["alarmId": alarmId, "held": false]
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      guard canHoldRing(alarmId: alarmId) else {
        return notHeld
      }
      let wasHeld = isRingHeld(alarmId: alarmId)
      let duration = AlarmSchedulerRingHoldPolicy.seconds(seconds)
      let backup = await scheduleNativeAlarmBackup(alarmId: alarmId, delaySeconds: duration)
      guard backup["scheduled"] as? Bool == true else {
        AlarmSchedulerNativeAlarmStore.clearHeldUntil(alarmId: alarmId)
        return notHeld
      }
      let heldUntil = (backup["scheduledFor"] as? Int64) ?? (nowMillis() + Int64(duration * 1000))
      AlarmSchedulerNativeAlarmStore.setHeldUntil(heldUntil, alarmId: alarmId)
      if !wasHeld {
        sendRingHoldStateChange(alarmId: alarmId, state: "held", heldUntil: heldUntil)
      }
      return ["alarmId": alarmId, "held": true, "resumesAt": heldUntil]
    }
    #endif
    return notHeld
  }

  func releaseRingHold(alarmId: String) async {
    guard isRingHeld(alarmId: alarmId) else {
      // Releasing a hold that is not there must never create a ring.
      AlarmSchedulerNativeAlarmStore.clearHeldUntil(alarmId: alarmId)
      return
    }
    // nil is the immediate default backup delay (0.1 s).
    _ = await scheduleNativeAlarmBackup(alarmId: alarmId, delaySeconds: nil)
    AlarmSchedulerNativeAlarmStore.clearHeldUntil(alarmId: alarmId)
  }

  func isRingHeld(alarmId: String) -> Bool {
    AlarmSchedulerRingHoldPolicy.isHeld(
      heldUntil: AlarmSchedulerNativeAlarmStore.heldUntil(alarmId: alarmId),
      isComplete: AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId),
      now: nowMillis()
    )
  }

  /// The occurrence the user is working through: the most recent one still marked ringing.
  func ringingOccurrence(alarmId: String) -> [String: Any]? {
    let now = nowMillis()
    return AlarmSchedulerOccurrenceStore.all(alarmId: alarmId).first { occurrence in
      occurrence["phase"] as? String == "ringing" &&
        AlarmSchedulerRingHoldPolicy.isRecentlyRinging(
          scheduledFor: (occurrence["scheduledFor"] as? NSNumber)?.int64Value ?? 0,
          now: now
        )
    }
  }

  /// Reported after alerting contexts and ahead of countdown ones: while held, the backup's
  /// countdown is the hold itself.
  func heldRingContext() -> [String: Any]? {
    let now = nowMillis()
    return AlarmSchedulerNativeAlarmStore.ringHolds()
      .filter { alarmId, heldUntil in
        AlarmSchedulerRingHoldPolicy.isHeld(
          heldUntil: heldUntil,
          isComplete: AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId),
          now: now
        )
      }
      .sorted { $0.value > $1.value }
      .lazy
      .compactMap { alarmId, heldUntil -> [String: Any]? in
        guard
          let storedAlarm = self.storedAlarms().first(where: { ($0["id"] as? String) == alarmId }),
          var context = self.alarmContext(from: storedAlarm, state: "held")
        else {
          return nil
        }
        context["heldUntil"] = heldUntil
        if let occurrence = self.ringingOccurrence(alarmId: alarmId) {
          context["occurrenceId"] = occurrence["occurrenceId"]
          context["relationship"] = occurrence["relationship"] ?? "primary"
          if let metadata = occurrence["metadata"] {
            context["metadata"] = metadata
          }
        }
        return context
      }
      .first
  }

  /// The alarm whose hold this backup timer belongs to, if any.
  func heldAlarmId(forBackupId backupId: String) -> String? {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      return AlarmSchedulerNativeAlarmStore.ringHolds().keys.first { alarmId in
        AlarmSchedulerRescheduler.backupAlarmId(for: alarmId)?.uuidString == backupId
      }
    }
    #endif
    return nil
  }

  func sendRingHoldStateChange(alarmId: String, state: String, heldUntil: Int64? = nil) {
    var event: [String: Any] = [
      "id": alarmId,
      "state": state,
      "timestamp": nowMillis()
    ]
    if let heldUntil {
      event["heldUntil"] = heldUntil
    }
    if let occurrence = ringingOccurrence(alarmId: alarmId) {
      event["occurrenceId"] = occurrence["occurrenceId"]
      event["relationship"] = occurrence["relationship"] ?? "primary"
      event["metadata"] = occurrence["metadata"]
    }
    if event["metadata"] == nil,
      let storedAlarm = storedAlarms().first(where: { ($0["id"] as? String) == alarmId }) {
      event["metadata"] = storedAlarm["metadata"]
    }
    sendEvent("onAlarmStateChange", event)
  }

  #if canImport(AlarmKit)
  /// Only an alarm that is ringing or already held qualifies, so a hold never creates a ring.
  /// AlarmKit's alert is usually gone by the time the app takes over, so a recent ringing occurrence
  /// counts as ringing too.
  @available(iOS 26.0, *)
  private func canHoldRing(alarmId: String) -> Bool {
    guard !AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId) else {
      return false
    }
    if isRingHeld(alarmId: alarmId) || ringingOccurrence(alarmId: alarmId) != nil {
      return true
    }
    let backupId = AlarmSchedulerRescheduler.backupAlarmId(for: alarmId)?.uuidString
    var relatedIds = Set(AlarmSchedulerNativeAlarmStore.retryAlarmIds(for: alarmId))
    relatedIds.insert(alarmId)
    AlarmSchedulerOccurrenceStore.all(alarmId: alarmId).forEach { occurrence in
      if let occurrenceId = occurrence["occurrenceId"] as? String {
        relatedIds.insert(occurrenceId)
      }
    }
    let activeAlarms = (try? AlarmManager.shared.alarms) ?? []
    return activeAlarms.contains { alarm in
      let id = alarm.id.uuidString
      switch mapAlarmState(alarm.state) {
      case "alerting":
        return id == backupId || relatedIds.contains(id)
      case "countdown":
        // The backstop counting down is a hold in all but name (scheduleNativeAlarmBackupAsync).
        // A deferred or follow-up timer counting down is a snooze, which a hold must not cut short.
        return id == backupId
      default:
        return false
      }
    }
  }
  #endif

  private func nowMillis() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
  }
}
