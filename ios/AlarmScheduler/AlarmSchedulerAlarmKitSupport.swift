import Foundation

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

func alarmSchedulerEffectiveSoundName(_ soundName: String?) -> String? {
  #if targetEnvironment(simulator)
  // iOS 26.x Simulator ToneLibrary crashes SpringBoard while preparing any external alarm tone:
  // -[AVAudioSession reporterID]: unrecognized selector. Real devices do not use this fallback.
  return nil
  #else
  guard let soundName, !soundName.isEmpty else {
    return nil
  }
  return soundName
  #endif
}

@available(iOS 26.0, *)
struct AlarmSchedulerMetadata: AlarmMetadata {
  let alarmId: String
  let title: String
  let values: [String: AlarmSchedulerMetadataValue]
}

@available(iOS 26.0, *)
struct AlarmSchedulerAlertPresentationResult {
  let alert: AlarmPresentation.Alert
  let debugState: [String: Any]
}

enum AlarmSchedulerMetadataValue: Codable, Hashable, Sendable {
  case string(String)
  case number(Double)
  case bool(Bool)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else {
      self = .string(try container.decode(String.self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    }
  }
}

@available(iOS 26.0, *)
struct AlarmSchedulerStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Stop Alarm"
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static var supportedModes: IntentModes { .foreground(.immediate) }

  @Parameter(title: "Alarm ID")
  var alarmId: String
  @Parameter(title: "Behavior")
  var behavior: String
  @Parameter(title: "Title")
  var alarmTitle: String
  @Parameter(title: "Hour")
  var hour: Int
  @Parameter(title: "Minute")
  var minute: Int
  @Parameter(title: "Weekdays")
  var weekdays: String
  @Parameter(title: "Sound Name")
  var soundName: String
  @Parameter(title: "Occurrence ID")
  var occurrenceId: String

  init() {
    alarmId = ""
    behavior = "openApp"
    alarmTitle = "Alarm"
    hour = 0
    minute = 0
    weekdays = ""
    soundName = ""
    occurrenceId = ""
  }

  init(
    alarmId: String,
    behavior: String,
    title: String,
    hour: Int,
    minute: Int,
    weekdays: [Int],
    soundName: String?,
    occurrenceId: String? = nil
  ) {
    self.alarmId = alarmId
    self.behavior = behavior
    self.alarmTitle = title
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays.map(String.init).joined(separator: ",")
    self.soundName = soundName ?? ""
    self.occurrenceId = occurrenceId ?? ""
  }

  func perform() async throws -> some IntentResult {
    let occurrence = occurrenceId.isEmpty
      ? AlarmSchedulerOccurrenceStore.activatePrimaryOccurrence(alarmId: alarmId)
      : AlarmSchedulerOccurrenceStore.markRinging(occurrenceId: occurrenceId)
    if occurrence?["relationship"] as? String == "primary" {
      AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: alarmId)
    }
    let shouldReschedule = behavior == "rescheduleImmediate" && !AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId)
    var details: [String: Any] = [
      "foregroundRequested": true
    ]
    if let resolvedOccurrenceId = occurrence?["occurrenceId"] as? String {
      details["occurrenceId"] = resolvedOccurrenceId
      details["relationship"] = occurrence?["relationship"] as? String ?? "primary"
    }
    if shouldReschedule {
      let backupResult = await AlarmSchedulerRescheduler.scheduleBackup(
        originalAlarmId: alarmId,
        title: alarmTitle,
        soundName: soundName.isEmpty ? nil : soundName,
        delaySeconds: AlarmSchedulerRescheduler.defaultBackupDelaySeconds
      )
      details["rescheduled"] = backupResult.scheduled
      details["rescheduledAlarmId"] = backupResult.backupAlarmId
      details["backupAlarmId"] = backupResult.backupAlarmId
      details["backupDelaySeconds"] = backupResult.delaySeconds
      if let scheduledFor = backupResult.scheduledFor {
        details["retryScheduledFor"] = scheduledFor
        details["backupScheduledFor"] = scheduledFor
      }
    }
    _ = AlarmSchedulerNativeAlarmStore.recordIntentHandoff(alarmId: alarmId, action: "nativeStop", details: details)
    return .result()
  }
}

@available(iOS 26.0, *)
struct AlarmSchedulerSecondaryOpenIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Open Alarm"
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static var supportedModes: IntentModes { .foreground(.immediate) }

  @Parameter(title: "Alarm ID")
  var alarmId: String
  @Parameter(title: "Occurrence ID")
  var occurrenceId: String

  init() {
    alarmId = ""
    occurrenceId = ""
  }

  init(alarmId: String, occurrenceId: String? = nil) {
    self.alarmId = alarmId
    self.occurrenceId = occurrenceId ?? ""
  }

  func perform() async throws -> some IntentResult {
    let occurrence = occurrenceId.isEmpty
      ? AlarmSchedulerOccurrenceStore.activatePrimaryOccurrence(alarmId: alarmId)
      : AlarmSchedulerOccurrenceStore.markRinging(occurrenceId: occurrenceId)
    if occurrence?["relationship"] as? String == "primary" {
      AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: alarmId)
    }
    var details: [String: Any] = [:]
    if let resolvedOccurrenceId = occurrence?["occurrenceId"] as? String {
      details["occurrenceId"] = resolvedOccurrenceId
      details["relationship"] = occurrence?["relationship"] as? String ?? "primary"
    }
    _ = AlarmSchedulerNativeAlarmStore.recordIntentHandoff(
      alarmId: alarmId,
      action: "secondaryOpen",
      details: details
    )
    return .result()
  }
}

@available(iOS 26.0, *)
struct AlarmSchedulerSecondaryRecordIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Record Alarm Action"
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static var supportedModes: IntentModes { .background }

  @Parameter(title: "Alarm ID")
  var alarmId: String
  @Parameter(title: "Occurrence ID")
  var occurrenceId: String

  init() {
    alarmId = ""
    occurrenceId = ""
  }

  init(alarmId: String, occurrenceId: String? = nil) {
    self.alarmId = alarmId
    self.occurrenceId = occurrenceId ?? ""
  }

  func perform() async throws -> some IntentResult {
    let occurrence = occurrenceId.isEmpty
      ? AlarmSchedulerOccurrenceStore.activatePrimaryOccurrence(alarmId: alarmId)
      : AlarmSchedulerOccurrenceStore.markRinging(occurrenceId: occurrenceId)
    if occurrence?["relationship"] as? String == "primary" {
      AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: alarmId)
    }
    var details: [String: Any] = [:]
    if let resolvedOccurrenceId = occurrence?["occurrenceId"] as? String {
      details["occurrenceId"] = resolvedOccurrenceId
      details["relationship"] = occurrence?["relationship"] as? String ?? "primary"
    }
    _ = AlarmSchedulerNativeAlarmStore.recordIntentHandoff(
      alarmId: alarmId,
      action: "secondaryOpen",
      details: details
    )
    return .result()
  }
}

@available(iOS 26.0, *)
struct AlarmSchedulerBackupScheduleResult {
  let alarmId: String
  let backupAlarmId: String
  let scheduled: Bool
  let scheduledFor: Int64?
  let delaySeconds: Double

  var dictionary: [String: Any] {
    var result: [String: Any] = [
      "alarmId": alarmId,
      "backupAlarmId": backupAlarmId,
      "scheduled": scheduled,
      "delaySeconds": delaySeconds
    ]
    if let scheduledFor {
      result["scheduledFor"] = scheduledFor
    }
    return result
  }
}

@available(iOS 26.0, *)
enum AlarmSchedulerRescheduler {
  static let defaultBackupDelaySeconds: Double = 0.1

  static func decodeWeekdays(_ value: String) -> [Int] {
    value
      .split(separator: ",")
      .compactMap { Int($0) }
      .filter { (1...7).contains($0) }
  }

  static func backupAlarmId(for alarmId: String) -> UUID? {
    guard let primary = UUID(uuidString: alarmId) else {
      return nil
    }
    let mask: UInt8 = 0xA7
    let bytes = primary.uuid
    let backupBytes = uuid_t(
      bytes.0 ^ mask,
      bytes.1 ^ mask,
      bytes.2 ^ mask,
      bytes.3 ^ mask,
      bytes.4 ^ mask,
      bytes.5 ^ mask,
      bytes.6 ^ mask,
      bytes.7 ^ mask,
      bytes.8 ^ mask,
      bytes.9 ^ mask,
      bytes.10 ^ mask,
      bytes.11 ^ mask,
      bytes.12 ^ mask,
      bytes.13 ^ mask,
      bytes.14 ^ mask,
      bytes.15 ^ mask
    )
    return UUID(uuid: backupBytes)
  }

  static func scheduleBackup(
    originalAlarmId: String,
    title: String,
    soundName: String?,
    delaySeconds: Double
  ) async -> AlarmSchedulerBackupScheduleResult {
    let normalizedDelaySeconds = max(0.1, delaySeconds)
    guard let alarmID = backupAlarmId(for: originalAlarmId) else {
      return AlarmSchedulerBackupScheduleResult(
        alarmId: originalAlarmId,
        backupAlarmId: "",
        scheduled: false,
        scheduledFor: nil,
        delaySeconds: normalizedDelaySeconds
      )
    }
    let backupAlarmId = alarmID.uuidString
    let backupScheduledFor = Int64(Date().addingTimeInterval(normalizedDelaySeconds).timeIntervalSince1970 * 1000)
    do {
      try? AlarmManager.shared.cancel(id: alarmID)
      let presentation = AlarmPresentation(
        alert: makeAlertPresentation(title: title)
      )
      let metadata = AlarmSchedulerMetadata(
        alarmId: originalAlarmId,
        title: title,
        values: [
          "alarmId": .string(originalAlarmId),
          "title": .string(title),
          "backupAlarmId": .string(backupAlarmId),
          "isBackupAlarm": .bool(true)
        ]
      )
      let attributes = AlarmAttributes(
        presentation: presentation,
        metadata: metadata,
        tintColor: Color.accentColor
      )
      _ = try await AlarmManager.shared.schedule(
        id: alarmID,
        configuration: AlarmManager.AlarmConfiguration.timer(
          duration: normalizedDelaySeconds,
          attributes: attributes,
          stopIntent: AlarmSchedulerStopIntent(
            alarmId: originalAlarmId,
            behavior: "rescheduleImmediate",
            title: title,
            hour: 0,
            minute: 0,
            weekdays: [],
            soundName: soundName,
            occurrenceId: backupAlarmId
          ),
          secondaryIntent: AlarmSchedulerSecondaryOpenIntent(
            alarmId: originalAlarmId,
            occurrenceId: backupAlarmId
          ),
          sound: makeAlarmSound(soundName)
        )
      )
      AlarmSchedulerNativeAlarmStore.addRetryAlarmId(backupAlarmId, for: originalAlarmId)
      return AlarmSchedulerBackupScheduleResult(
        alarmId: originalAlarmId,
        backupAlarmId: backupAlarmId,
        scheduled: true,
        scheduledFor: backupScheduledFor,
        delaySeconds: normalizedDelaySeconds
      )
    } catch {
      return AlarmSchedulerBackupScheduleResult(
        alarmId: originalAlarmId,
        backupAlarmId: backupAlarmId,
        scheduled: false,
        scheduledFor: nil,
        delaySeconds: normalizedDelaySeconds
      )
    }
  }

  private static func makeAlertPresentation(title: String) -> AlarmPresentation.Alert {
    return AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: title),
      stopButton: AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
    )
  }

  private static func makeAlarmSound(_ soundName: String?) -> AlertConfiguration.AlertSound {
    guard let soundName = alarmSchedulerEffectiveSoundName(soundName) else {
      return .default
    }
    return .named(soundName)
  }
}
#endif
