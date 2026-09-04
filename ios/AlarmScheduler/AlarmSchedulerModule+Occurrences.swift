import Foundation

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

extension AlarmSchedulerModule {
  func resolvedOccurrenceOptions(_ options: IosAlarmOptionsRecord?, title: String) -> [String: Any] {
    let alertActionMode = options?.alertActionMode?.nilIfEmpty == "openAppOnly" ? "openAppOnly" : "default"
    var result: [String: Any] = [
      "alertTitle": options?.alertTitle?.nilIfEmpty ?? title,
      "alertActionMode": alertActionMode,
      "stopButtonTitle": options?.stopButtonTitle?.nilIfEmpty ?? "Stop",
      "stopIntentBehavior": options?.stopIntentBehavior?.nilIfEmpty ?? "recordOnly",
      "secondaryButtonBehavior": options?.secondaryButtonBehavior?.nilIfEmpty ?? "openApp"
    ]
    let secondaryTitle = options?.secondaryButtonTitle?.nilIfEmpty
      ?? (alertActionMode == "openAppOnly" ? "Open app" : nil)
    if let secondaryTitle {
      result["secondaryButtonTitle"] = secondaryTitle
    }
    if let countdownTitle = options?.countdownTitle?.nilIfEmpty {
      result["countdownTitle"] = countdownTitle
    }
    return result
  }

  func resolveAlarmOccurrence(
    occurrenceId: String,
    resolution: AlarmOccurrenceResolutionRecord
  ) async throws -> [String: Any] {
    guard !occurrenceId.isEmpty else {
      throw InvalidAlarmException("occurrenceId must not be empty.")
    }
    guard resolution.outcome == "completed" || resolution.outcome == "deferred" else {
      throw InvalidAlarmException("outcome must be completed or deferred.")
    }
    if resolution.outcome == "deferred" && resolution.next?.relationship != "deferred" {
      throw InvalidAlarmException("A deferred resolution requires a deferred next occurrence.")
    }
    if let next = resolution.next {
      guard next.relationship == "deferred" || next.relationship == "followUp" else {
        throw InvalidAlarmException("next.relationship must be deferred or followUp.")
      }
      guard next.delaySeconds.isFinite && next.delaySeconds > 0 else {
        throw InvalidAlarmException("next.delaySeconds must be greater than zero.")
      }
    }

    let alarmId = AlarmSchedulerOccurrenceStore.alarmId(for: occurrenceId)
    if let key = resolution.idempotencyKey?.nilIfEmpty,
      let previous = AlarmSchedulerOccurrenceStore.resolution(alarmId: alarmId, idempotencyKey: key) {
      return previous
    }
    guard let stored = storedAlarms().first(where: { ($0["id"] as? String) == alarmId }) else {
      throw InvalidAlarmException("No alarm definition exists for occurrence \(occurrenceId).")
    }

    AlarmSchedulerNativeAlarmStore.complete(alarmId: alarmId)
    await cancelNativeAndRetryAlarms(originalAlarmId: alarmId)
    AlarmSchedulerNativeAlarmStore.clearActions(alarmId: alarmId)
    AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: occurrenceId, phase: "completed")

    var nextOccurrence: [String: Any]?
    var status = "resolved"
    if let next = resolution.next {
      AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: alarmId)
      let nextOccurrenceId = UUID().uuidString
      let delaySeconds = max(0.1, next.delaySeconds)
      let scheduledFor = Int64(Date().addingTimeInterval(delaySeconds).timeIntervalSince1970 * 1000)
      var metadata = stored["metadata"] as? [String: Any] ?? [:]
      next.metadata?.forEach { metadata[$0.key] = $0.value }
      metadata["occurrenceId"] = nextOccurrenceId
      metadata["relationship"] = next.relationship
      let occurrence: [String: Any] = [
        "occurrenceId": nextOccurrenceId,
        "alarmId": alarmId,
        "parentOccurrenceId": occurrenceId,
        "scheduledFor": scheduledFor,
        "relationship": next.relationship,
        "phase": "scheduled",
        "metadata": normalizeMetadata(metadata, id: alarmId, title: stored["title"] as? String ?? "Alarm")
      ]
      AlarmSchedulerOccurrenceStore.save(occurrence)
      if await scheduleOccurrenceTimer(occurrence: occurrence, storedAlarm: stored, delaySeconds: delaySeconds) {
        nextOccurrence = occurrence
      } else {
        AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: nextOccurrenceId, phase: "cancelled")
        AlarmSchedulerNativeAlarmStore.complete(alarmId: alarmId)
        status = "resolvedWithoutNext"
      }
    }

    var result: [String: Any] = [
      "alarmId": alarmId,
      "resolvedOccurrenceId": occurrenceId,
      "outcome": resolution.outcome,
      "status": status
    ]
    if let nextOccurrence {
      result["nextOccurrence"] = nextOccurrence
    }
    if let key = resolution.idempotencyKey?.nilIfEmpty {
      AlarmSchedulerOccurrenceStore.saveResolution(alarmId: alarmId, idempotencyKey: key, result: result)
    }
    return result
  }

  func cancelAlarmOccurrence(occurrenceId: String) async -> Bool {
    guard let occurrence = AlarmSchedulerOccurrenceStore.occurrence(id: occurrenceId),
      let alarmId = occurrence["alarmId"] as? String,
      occurrence["phase"] as? String != "completed",
      occurrence["phase"] as? String != "cancelled" else {
      return false
    }

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *), let nativeId = UUID(uuidString: occurrenceId) {
      try? AlarmManager.shared.cancel(id: nativeId)
      AlarmSchedulerNativeAlarmStore.removeRetryAlarmId(occurrenceId, for: alarmId)
      AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: occurrenceId, phase: "cancelled")
      let hasAnotherActiveOccurrence = AlarmSchedulerOccurrenceStore.all(alarmId: alarmId).contains {
        ($0["occurrenceId"] as? String) != occurrenceId &&
          ($0["relationship"] as? String) != "primary" &&
          (($0["phase"] as? String) == "scheduled" || ($0["phase"] as? String) == "ringing")
      }
      if !hasAnotherActiveOccurrence {
        AlarmSchedulerNativeAlarmStore.complete(alarmId: alarmId)
      }
      return true
    }
    #endif
    return false
  }

  private func scheduleOccurrenceTimer(
    occurrence: [String: Any],
    storedAlarm: [String: Any],
    delaySeconds: Double
  ) async -> Bool {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *),
      let occurrenceId = occurrence["occurrenceId"] as? String,
      let nativeId = UUID(uuidString: occurrenceId),
      let alarmId = occurrence["alarmId"] as? String {
      let title = storedAlarm["title"] as? String ?? "Alarm"
      let soundName = storedAlarm["iosSoundName"] as? String
      let metadata = occurrence["metadata"] as? [String: Any] ?? [:]
      let options = storedAlarm["occurrenceOptions"] as? [String: Any] ?? resolvedOccurrenceOptions(nil, title: title)
      let alertActionMode = normalizeAlertActionMode(options["alertActionMode"] as? String)
      let secondaryButtonTitle = options["secondaryButtonTitle"] as? String
      let secondaryButtonBehaviorName = options["secondaryButtonBehavior"] as? String
      let secondaryButton = secondaryButtonTitle.map {
        AlarmButton(
          text: LocalizedStringResource(stringLiteral: $0),
          textColor: .white,
          systemImageName: "app.badge"
        )
      }
      let alertPresentation = makeAlertPresentation(
        title: options["alertTitle"] as? String ?? title,
        alertActionMode: alertActionMode,
        stopButtonTitle: options["stopButtonTitle"] as? String ?? "Stop",
        secondaryButton: secondaryButton,
        secondaryButtonBehavior: normalizeSecondaryButtonBehavior(
          secondaryButtonBehaviorName,
          hasSecondaryButton: secondaryButton != nil
        ),
        stopIntentBehavior: normalizeStopIntentBehavior(options["stopIntentBehavior"] as? String),
        secondaryButtonBehaviorName: normalizeSecondaryButtonBehaviorName(
          secondaryButtonBehaviorName,
          hasSecondaryButton: secondaryButton != nil
        )
      )
      let presentation = AlarmPresentation(
        alert: alertPresentation.alert,
        countdown: (options["countdownTitle"] as? String).map {
          AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: $0))
        }
      )
      let attributes = AlarmAttributes(
        presentation: presentation,
        metadata: AlarmSchedulerMetadata(
          alarmId: alarmId,
          title: title,
          values: alarmKitMetadataValues(metadata)
        ),
        tintColor: Color.accentColor
      )
      do {
        _ = try await AlarmManager.shared.schedule(
          id: nativeId,
          configuration: AlarmManager.AlarmConfiguration.timer(
            duration: delaySeconds,
            attributes: attributes,
            stopIntent: AlarmSchedulerStopIntent(
              alarmId: alarmId,
              behavior: normalizeStopIntentBehavior(options["stopIntentBehavior"] as? String),
              title: title,
              hour: 0,
              minute: 0,
              weekdays: [],
              soundName: soundName
            ),
            secondaryIntent: makeSecondaryIntent(id: alarmId, behavior: secondaryButtonBehaviorName),
            sound: makeAlarmSound(soundName)
          )
        )
        AlarmSchedulerNativeAlarmStore.addRetryAlarmId(occurrenceId, for: alarmId)
        return true
      } catch {
        return false
      }
    }
    #endif
    return false
  }
}

private extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
