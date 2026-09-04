import Foundation

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import SwiftUI
#endif

extension AlarmSchedulerModule {
  func schedule(_ alarm: AlarmScheduleRecord) async throws -> [String: Any] {
    let id = alarm.id?.isEmpty == false ? alarm.id! : UUID().uuidString
    AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: id)
    cancelActiveOccurrenceRecords(alarmId: id)
    let hour = try requireHour(alarm.hour)
    let minute = try requireMinute(alarm.minute)
    let title = alarm.title?.isEmpty == false ? alarm.title! : "Alarm"
    let weekdays = try normalizeWeekdays(alarm.weekdays)
    let metadata = normalizeMetadata(alarm.ios?.metadata, id: id, title: title)
    let timestamp = alarm.timestamp.flatMap { $0 > Date().timeIntervalSince1970 * 1000 ? Int64($0) : nil }
      ?? nextTriggerTimestamp(hour: hour, minute: minute, weekdays: weekdays)
    let runtimeSoundUri = normalizedSoundName(alarm.ios?.soundUri) ?? normalizedSoundName(alarm.soundUri)
    let soundName: String?
    if alarm.ios?.silent == true {
      removeRuntimeSound(alarmId: id)
      soundName = try bundledSilentSoundName()
    } else if let runtimeSoundUri {
      soundName = try prepareRuntimeSound(uri: runtimeSoundUri, alarmId: id)
    } else {
      removeRuntimeSound(alarmId: id)
      soundName = normalizedSoundName(alarm.ios?.soundName)
    }
    var alarmKitDebugState: [String: Any]?

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      alarmKitDebugState = try await scheduleAlarmKit(
        id: id,
        title: title,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        options: alarm.ios,
        metadata: metadata,
        soundName: soundName,
        silent: alarm.ios?.silent == true
      )
    } else {
      throw UnsupportedAlarmException("AlarmKit requires iOS 26 or newer.")
    }
    #else
    throw UnsupportedAlarmException("This build was compiled without AlarmKit. Build with the iOS 26 SDK or newer to schedule native iOS alarms.")
    #endif

    var stored: [String: Any] = [
      "id": id,
      "hour": hour,
      "minute": minute,
      "title": title,
      "weekdays": weekdays,
      "timestamp": timestamp,
      "platform": "ios",
      "metadata": metadata
    ]
    if let soundName {
      stored["iosSoundName"] = soundName
    }
    if let alarmKitDebugState {
      stored["alarmKitDebugState"] = alarmKitDebugState
    }
    stored["occurrenceOptions"] = resolvedOccurrenceOptions(alarm.ios, title: title)
    save(alarm: stored)
    recordPrimaryOccurrence(alarmId: id, scheduledFor: timestamp, metadata: metadata)
    return stored
  }

  func cancel(id: String) async -> Bool {
    var didCancelNativeAlarm = false

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      if let uuid = UUID(uuidString: id) {
        try? AlarmManager.shared.cancel(id: uuid)
        didCancelNativeAlarm = true
      }
      if let backupId = AlarmSchedulerRescheduler.backupAlarmId(for: id) {
        try? AlarmManager.shared.cancel(id: backupId)
        didCancelNativeAlarm = true
      }
      for retryAlarmId in AlarmSchedulerNativeAlarmStore.retryAlarmIds(for: id) {
        guard let uuid = UUID(uuidString: retryAlarmId) else {
          continue
        }
        try? AlarmManager.shared.cancel(id: uuid)
        didCancelNativeAlarm = true
      }
      AlarmSchedulerNativeAlarmStore.clearRetryAlarmIds(for: id)
    }
    #endif

    AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: id)
    AlarmSchedulerNativeAlarmStore.clearActions(alarmId: id)
    cancelActiveOccurrenceRecords(alarmId: id)
    let didRemoveStoredAlarm = remove(id: id)
    removeRuntimeSound(alarmId: id)
    return didCancelNativeAlarm || didRemoveStoredAlarm
  }

  func cancelNativeAndRetryAlarms(originalAlarmId: String) async {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      if let uuid = UUID(uuidString: originalAlarmId) {
        try? AlarmManager.shared.cancel(id: uuid)
      }
      if let backupId = AlarmSchedulerRescheduler.backupAlarmId(for: originalAlarmId) {
        try? AlarmManager.shared.cancel(id: backupId)
      }
      for retryAlarmId in AlarmSchedulerNativeAlarmStore.retryAlarmIds(for: originalAlarmId) {
        guard let uuid = UUID(uuidString: retryAlarmId) else {
          continue
        }
        try? AlarmManager.shared.cancel(id: uuid)
      }
      AlarmSchedulerNativeAlarmStore.clearRetryAlarmIds(for: originalAlarmId)
    }
    #endif
  }

  func scheduleNativeAlarmBackup(alarmId: String, delaySeconds: Double?) async -> [String: Any] {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      guard !AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId) else {
        return [
          "alarmId": alarmId,
          "backupAlarmId": AlarmSchedulerRescheduler.backupAlarmId(for: alarmId)?.uuidString ?? "",
          "scheduled": false,
          "delaySeconds": delaySeconds ?? AlarmSchedulerRescheduler.defaultBackupDelaySeconds
        ]
      }
      let title = storedAlarms().first(where: { ($0["id"] as? String) == alarmId })?["title"] as? String ?? "Alarm"
      let soundName = storedAlarms().first(where: { ($0["id"] as? String) == alarmId })?["iosSoundName"] as? String
      return await AlarmSchedulerRescheduler.scheduleBackup(
        originalAlarmId: alarmId,
        title: title,
        soundName: soundName,
        delaySeconds: delaySeconds ?? AlarmSchedulerRescheduler.defaultBackupDelaySeconds
      ).dictionary
    }
    #endif

    return [
      "alarmId": alarmId,
      "backupAlarmId": "",
      "scheduled": false,
      "delaySeconds": delaySeconds ?? 0.1
    ]
  }

  func cancelNativeAlarmBackup(alarmId: String) async -> Bool {
    var didCancel = false

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      if let backupId = AlarmSchedulerRescheduler.backupAlarmId(for: alarmId) {
        try? AlarmManager.shared.cancel(id: backupId)
        didCancel = true
      }
      for retryAlarmId in AlarmSchedulerNativeAlarmStore.retryAlarmIds(for: alarmId) {
        guard let uuid = UUID(uuidString: retryAlarmId) else {
          continue
        }
        try? AlarmManager.shared.cancel(id: uuid)
        didCancel = true
      }
      AlarmSchedulerNativeAlarmStore.clearRetryAlarmIds(for: alarmId)
    }
    #endif

    return didCancel
  }

  func currentAlarmContext() -> [String: Any]? {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      let activeAlarms = (try? AlarmManager.shared.alarms) ?? []
      let activeIds = Set(activeAlarms.map { $0.id.uuidString })
      let backupIdByPrimaryId = Dictionary(uniqueKeysWithValues: storedAlarms().compactMap { alarm -> (String, String)? in
        guard
          let id = alarm["id"] as? String,
          let backupId = AlarmSchedulerRescheduler.backupAlarmId(for: id)?.uuidString
        else {
          return nil
        }
        return (backupId, id)
      })
      let storedById = Dictionary(uniqueKeysWithValues: storedAlarms().compactMap { alarm -> (String, [String: Any])? in
        guard let id = alarm["id"] as? String else {
          return nil
        }
        return (id, alarm)
      })

      let activeContexts = activeAlarms.compactMap { alarm -> [String: Any]? in
        let id = alarm.id.uuidString
        if let occurrence = AlarmSchedulerOccurrenceStore.occurrence(id: id),
          let primaryId = occurrence["alarmId"] as? String,
          let storedAlarm = storedById[primaryId],
          var context = alarmContext(from: storedAlarm, state: mapAlarmState(alarm.state), nativeAlarmId: id) {
          let state = mapAlarmState(alarm.state)
          let resolvedOccurrence: [String: Any]
          if state == "alerting",
            occurrence["relationship"] as? String == "primary",
            occurrence["occurrenceId"] as? String == primaryId {
            AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: id, phase: "cancelled")
            resolvedOccurrence = activePrimaryOccurrence(
              alarmId: primaryId,
              metadata: storedAlarm["metadata"] as? [String: Any] ?? [:]
            )
          } else {
            resolvedOccurrence = occurrence
          }
          context["occurrenceId"] = resolvedOccurrence["occurrenceId"]
          context["relationship"] = resolvedOccurrence["relationship"] ?? "primary"
          if let metadata = resolvedOccurrence["metadata"] {
            context["metadata"] = metadata
          }
          return context
        }
        if let primaryId = backupIdByPrimaryId[id], let storedAlarm = storedById[primaryId] {
          return alarmContext(from: storedAlarm, state: mapAlarmState(alarm.state), nativeAlarmId: id)
        }
        guard let storedAlarm = storedById[id] else {
          return [
            "id": id,
            "metadata": normalizeMetadata(nil, id: id, title: "Alarm"),
            "state": mapAlarmState(alarm.state)
          ]
        }
        let state = mapAlarmState(alarm.state)
        let occurrence = state == "alerting"
          ? activePrimaryOccurrence(
            alarmId: id,
            metadata: storedAlarm["metadata"] as? [String: Any] ?? [:]
          )
          : AlarmSchedulerOccurrenceStore.all(alarmId: id).first(where: {
            ($0["relationship"] as? String) == "primary" &&
              (($0["phase"] as? String) == "scheduled" || ($0["phase"] as? String) == "ringing")
          })
        guard var context = alarmContext(from: storedAlarm, state: state, nativeAlarmId: id) else {
          return nil
        }
        if let occurrence {
          context["occurrenceId"] = occurrence["occurrenceId"]
          context["relationship"] = "primary"
          context["metadata"] = occurrence["metadata"] ?? storedAlarm["metadata"]
        }
        return context
      }

      if let alertingContext = activeContexts.first(where: { ($0["state"] as? String) == "alerting" }) {
        return alertingContext
      }
      if let countdownContext = activeContexts.first(where: { ($0["state"] as? String) == "countdown" }) {
        return countdownContext
      }
      if let pausedContext = activeContexts.first(where: { ($0["state"] as? String) == "paused" }) {
        return pausedContext
      }
      if let recentFiredContext = recentFiredAlarmContext(excluding: activeIds) {
        return recentFiredContext
      }
      return activeContexts.first(where: { ($0["state"] as? String) == "scheduled" })
    }
    #endif

    return nil
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  private func scheduleAlarmKit(
    id: String,
    title: String,
    hour: Int,
    minute: Int,
    weekdays: [Int],
    options: IosAlarmOptionsRecord?,
    metadata: [String: Any],
    soundName: String?,
    silent: Bool
  ) async throws -> [String: Any] {
    guard let alarmID = UUID(uuidString: id) else {
      throw InvalidAlarmException("Alarm id must be a UUID string on iOS.")
    }

    let alertTitle = options?.alertTitle?.isEmpty == false ? options!.alertTitle! : title
    let alertActionMode = normalizeAlertActionMode(options?.alertActionMode)
    let stopButtonTitle = options?.stopButtonTitle?.isEmpty == false ? options!.stopButtonTitle! : "Stop"
    let secondaryButtonTitle = options?.secondaryButtonTitle?.isEmpty == false
      ? options!.secondaryButtonTitle!
      : (alertActionMode == "openAppOnly" ? "Open app" : nil)
    let secondaryButtonBehavior = normalizeSecondaryButtonBehavior(options?.secondaryButtonBehavior, hasSecondaryButton: secondaryButtonTitle != nil)
    let secondaryButton = secondaryButtonTitle.map {
      AlarmButton(text: LocalizedStringResource(stringLiteral: $0), textColor: .white, systemImageName: "app.badge")
    }
    let alertPresentation = makeAlertPresentation(
      title: alertTitle,
      alertActionMode: alertActionMode,
      stopButtonTitle: stopButtonTitle,
      secondaryButton: secondaryButton,
      secondaryButtonBehavior: secondaryButtonBehavior,
      stopIntentBehavior: normalizeStopIntentBehavior(options?.stopIntentBehavior),
      secondaryButtonBehaviorName: normalizeSecondaryButtonBehaviorName(options?.secondaryButtonBehavior, hasSecondaryButton: secondaryButtonTitle != nil)
    )
    let presentation = AlarmPresentation(alert: alertPresentation.alert)
    let attributes = AlarmAttributes(
      presentation: presentation,
      metadata: AlarmSchedulerMetadata(alarmId: id, title: title, values: alarmKitMetadataValues(metadata)),
      tintColor: Color.accentColor
    )
    let schedule = try makeAlarmKitSchedule(hour: hour, minute: minute, weekdays: weekdays)
    let effectiveSoundName = alarmSchedulerEffectiveSoundName(soundName)
    let stopIntent = makeStopIntent(
      id: id,
      title: title,
      hour: hour,
      minute: minute,
      weekdays: weekdays,
      behavior: normalizeStopIntentBehavior(options?.stopIntentBehavior),
      soundName: effectiveSoundName
    )
    let secondaryIntent = makeSecondaryIntent(id: id, behavior: options?.secondaryButtonBehavior)
    _ = try await AlarmManager.shared.schedule(
      id: alarmID,
      configuration: AlarmManager.AlarmConfiguration.alarm(
        schedule: schedule,
        attributes: attributes,
        stopIntent: stopIntent,
        secondaryIntent: secondaryIntent,
        sound: makeAlarmSound(effectiveSoundName)
      )
    )
    var debugState = alertPresentation.debugState
    debugState["sound"] = silent ? "silent" : (effectiveSoundName == nil ? "default" : "named")
    if let effectiveSoundName {
      debugState["soundName"] = effectiveSoundName
    } else if soundName != nil {
      debugState["soundFallbackReason"] = "iosSimulatorCustomSoundUnsupported"
    }
    return debugState
  }

  @available(iOS 26.0, *)
  func makeAlertPresentation(
    title: String,
    alertActionMode: String,
    stopButtonTitle: String,
    secondaryButton: AlarmButton?,
    secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior?,
    stopIntentBehavior: String,
    secondaryButtonBehaviorName: String
  ) -> AlarmSchedulerAlertPresentationResult {
    let runtimeSupportsSecondaryOnlyAlert: Bool
    if #available(iOS 26.1, *) {
      runtimeSupportsSecondaryOnlyAlert = true
    } else {
      runtimeSupportsSecondaryOnlyAlert = false
    }
    let shouldUseSecondaryOnly = alertActionMode == "openAppOnly" && runtimeSupportsSecondaryOnlyAlert
    let debugState: [String: Any] = [
      "alertActionMode": alertActionMode,
      "stopButtonIncluded": !shouldUseSecondaryOnly,
      "secondaryButtonIncluded": secondaryButton != nil,
      "secondaryButtonBehavior": secondaryButtonBehaviorName,
      "stopIntentBehavior": stopIntentBehavior,
      "alertInitializer": shouldUseSecondaryOnly ? "secondaryOnly" : "legacyStopButton",
      "runtimeSupportsSecondaryOnlyAlert": runtimeSupportsSecondaryOnlyAlert
    ]
    if alertActionMode == "openAppOnly" {
      if #available(iOS 26.1, *) {
        return AlarmSchedulerAlertPresentationResult(
          alert: AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: secondaryButton,
            secondaryButtonBehavior: secondaryButtonBehavior
          ),
          debugState: debugState
        )
      }
    }
    return AlarmSchedulerAlertPresentationResult(
      alert: AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: stopButtonTitle), textColor: .white, systemImageName: "stop.fill"),
        secondaryButton: secondaryButton,
        secondaryButtonBehavior: secondaryButtonBehavior
      ),
      debugState: debugState
    )
  }

  @available(iOS 26.0, *)
  func normalizeAlertActionMode(_ mode: String?) -> String {
    switch mode ?? "default" {
    case "openAppOnly":
      return "openAppOnly"
    default:
      return "default"
    }
  }

  @available(iOS 26.0, *)
  func normalizeStopIntentBehavior(_ behavior: String?) -> String {
    switch behavior ?? "recordOnly" {
    case "recordOnly", "openApp", "rescheduleImmediate":
      return behavior ?? "recordOnly"
    default:
      return "recordOnly"
    }
  }

  @available(iOS 26.0, *)
  func normalizeSecondaryButtonBehaviorName(
    _ behavior: String?,
    hasSecondaryButton: Bool
  ) -> String {
    guard hasSecondaryButton else {
      return "none"
    }
    switch behavior ?? "openApp" {
    case "openApp", "recordOnly", "none":
      return behavior ?? "openApp"
    default:
      return "openApp"
    }
  }

  @available(iOS 26.0, *)
  func makeStopIntent(
    id: String,
    title: String,
    hour: Int,
    minute: Int,
    weekdays: [Int],
    behavior: String?,
    soundName: String?
  ) -> (any LiveActivityIntent)? {
    switch behavior ?? "recordOnly" {
    case "recordOnly", "openApp", "rescheduleImmediate":
      return AlarmSchedulerStopIntent(
        alarmId: id,
        behavior: behavior ?? "recordOnly",
        title: title,
        hour: hour,
        minute: minute,
        weekdays: weekdays,
        soundName: soundName
      )
    default:
      return nil
    }
  }

  @available(iOS 26.0, *)
  func makeSecondaryIntent(
    id: String,
    behavior: String?,
    occurrenceId: String? = nil
  ) -> (any LiveActivityIntent)? {
    switch behavior ?? "openApp" {
    case "openApp":
      return AlarmSchedulerSecondaryOpenIntent(alarmId: id, occurrenceId: occurrenceId)
    case "recordOnly":
      return AlarmSchedulerSecondaryRecordIntent(alarmId: id, occurrenceId: occurrenceId)
    default:
      return nil
    }
  }

  @available(iOS 26.0, *)
  func normalizeSecondaryButtonBehavior(
    _ behavior: String?,
    hasSecondaryButton: Bool
  ) -> AlarmPresentation.Alert.SecondaryButtonBehavior? {
    guard hasSecondaryButton else {
      return nil
    }
    switch behavior ?? "openApp" {
    case "openApp", "recordOnly":
      return .custom
    case "none":
      return nil
    default:
      return .custom
    }
  }

  @available(iOS 26.0, *)
  private func makeAlarmKitSchedule(hour: Int, minute: Int, weekdays: [Int]) throws -> Alarm.Schedule {
    let time = Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
    if weekdays.isEmpty {
      return .relative(.init(time: time, repeats: .never))
    }
    return .relative(.init(time: time, repeats: .weekly(weekdays.map(toLocaleWeekday))))
  }

  @available(iOS 26.0, *)
  private func toLocaleWeekday(_ weekday: Int) -> Locale.Weekday {
    switch weekday {
    case 1: return .monday
    case 2: return .tuesday
    case 3: return .wednesday
    case 4: return .thursday
    case 5: return .friday
    case 6: return .saturday
    case 7: return .sunday
    default: return .monday
    }
  }
  #endif

  private func requireHour(_ hour: Int) throws -> Int {
    guard (0...23).contains(hour) else {
      throw InvalidAlarmException("hour must be between 0 and 23.")
    }
    return hour
  }

  private func requireMinute(_ minute: Int) throws -> Int {
    guard (0...59).contains(minute) else {
      throw InvalidAlarmException("minute must be between 0 and 59.")
    }
    return minute
  }

  private func normalizeWeekdays(_ weekdays: [Int]?) throws -> [Int] {
    let normalized = Array(Set(weekdays ?? [])).sorted()
    guard normalized.allSatisfy({ (1...7).contains($0) }) else {
      throw InvalidAlarmException("weekdays must use 1=Monday through 7=Sunday.")
    }
    return normalized
  }
}
