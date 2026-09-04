import ExpoModulesCore
import AVFoundation
import Foundation
import UIKit

#if canImport(AlarmKit)
import ActivityKit
import AlarmKit
import AppIntents
import SwiftUI

private func alarmSchedulerEffectiveSoundName(_ soundName: String?) -> String? {
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
#endif

struct AlarmScheduleRecord: Record {
  @Field var id: String?
  @Field var hour: Int = -1
  @Field var minute: Int = -1
  @Field var title: String?
  @Field var weekdays: [Int]?
  @Field var timestamp: Double?
  @Field var showUi: Bool = false
  @Field var soundUri: String?
  @Field var ios: IosAlarmOptionsRecord?
}

struct IosAlarmOptionsRecord: Record {
  @Field var metadata: [String: Any]?
  @Field var alertTitle: String?
  @Field var alertActionMode: String?
  @Field var stopButtonTitle: String?
  @Field var secondaryButtonTitle: String?
  @Field var countdownTitle: String?
  @Field var stopIntentBehavior: String?
  @Field var secondaryButtonBehavior: String?
  @Field var soundUri: String?
  @Field var soundName: String?
}

private enum AlarmSchedulerNativeAlarmStore {
  private static let actionsKey = "alarm_scheduler_actions"
  private static let completionsKey = "alarm_scheduler_completed_ids"
  private static let retryIdsKey = "alarm_scheduler_retry_ids_by_alarm"
  private static let pendingHandoffKey = "alarm_scheduler_pending_handoff"
  private static let intentDebugCountsKey = "alarm_scheduler_intent_debug_counts"
  static let actionRecordedNotification = Notification.Name("expo.modules.alarm.actionRecorded")

  static func all() -> [[String: Any]] {
    UserDefaults.standard.array(forKey: actionsKey) as? [[String: Any]] ?? []
  }

  static func record(
    alarmId: String,
    action: String,
    timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
    details: [String: Any] = [:]
  ) -> [String: Any] {
    var event: [String: Any] = [
      "id": UUID().uuidString,
      "alarmId": alarmId,
      "action": action,
      "timestamp": timestamp
    ]
    details.forEach { key, value in
      event[key] = value
    }
    var actions = all()
    actions.append(event)
    UserDefaults.standard.set(actions, forKey: actionsKey)
    NotificationCenter.default.post(name: actionRecordedNotification, object: nil, userInfo: event)
    return event
  }

  static func recordIntentHandoff(
    alarmId: String,
    action: String,
    timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
    details: [String: Any] = [:]
  ) -> [String: Any] {
    incrementIntentInvocation(action: action, alarmId: alarmId)
    let event = record(alarmId: alarmId, action: action, timestamp: timestamp, details: details)
    UserDefaults.standard.set(event, forKey: pendingHandoffKey)
    return event
  }

  static func pendingHandoff() -> [String: Any]? {
    UserDefaults.standard.dictionary(forKey: pendingHandoffKey)
  }

  static func clearPendingHandoff() {
    UserDefaults.standard.removeObject(forKey: pendingHandoffKey)
  }

  static func clear(ids: [String]?) {
    guard let ids, !ids.isEmpty else {
      UserDefaults.standard.removeObject(forKey: actionsKey)
      return
    }
    let idsToRemove = Set(ids)
    let remaining = all().filter { action in
      guard let id = action["id"] as? String else {
        return true
      }
      return !idsToRemove.contains(id)
    }
    UserDefaults.standard.set(remaining, forKey: actionsKey)
  }

  static func clearActions(alarmId: String) {
    let remaining = all().filter { action in
      action["alarmId"] as? String != alarmId
    }
    UserDefaults.standard.set(remaining, forKey: actionsKey)
    if pendingHandoff()?["alarmId"] as? String == alarmId {
      clearPendingHandoff()
    }
  }

  static func complete(alarmId: String) {
    var ids = completedAlarmIds()
    ids.insert(alarmId)
    UserDefaults.standard.set(Array(ids), forKey: completionsKey)
  }

  static func resetCompletion(alarmId: String) {
    var ids = completedAlarmIds()
    ids.remove(alarmId)
    UserDefaults.standard.set(Array(ids), forKey: completionsKey)
  }

  static func isComplete(alarmId: String) -> Bool {
    completedAlarmIds().contains(alarmId)
  }

  private static func completedAlarmIds() -> Set<String> {
    Set(UserDefaults.standard.stringArray(forKey: completionsKey) ?? [])
  }

  static func addRetryAlarmId(_ retryAlarmId: String, for alarmId: String) {
    var allRetryIds = retryIdsByAlarmId()
    var ids = allRetryIds[alarmId] ?? []
    if !ids.contains(retryAlarmId) {
      ids.append(retryAlarmId)
    }
    allRetryIds[alarmId] = ids
    UserDefaults.standard.set(allRetryIds, forKey: retryIdsKey)
  }

  static func retryAlarmIds(for alarmId: String) -> [String] {
    retryIdsByAlarmId()[alarmId] ?? []
  }

  static func clearRetryAlarmIds(for alarmId: String) {
    var allRetryIds = retryIdsByAlarmId()
    allRetryIds.removeValue(forKey: alarmId)
    UserDefaults.standard.set(allRetryIds, forKey: retryIdsKey)
  }

  private static func retryIdsByAlarmId() -> [String: [String]] {
    UserDefaults.standard.dictionary(forKey: retryIdsKey) as? [String: [String]] ?? [:]
  }

  static func intentDebugCounts(alarmId: String) -> [String: Int] {
    intentDebugCountsByAlarmId()[alarmId] ?? [:]
  }

  private static func incrementIntentInvocation(action: String, alarmId: String) {
    var countsByAlarmId = intentDebugCountsByAlarmId()
    var counts = countsByAlarmId[alarmId] ?? [:]
    counts[action] = (counts[action] ?? 0) + 1
    countsByAlarmId[alarmId] = counts
    UserDefaults.standard.set(countsByAlarmId, forKey: intentDebugCountsKey)
  }

  private static func intentDebugCountsByAlarmId() -> [String: [String: Int]] {
    UserDefaults.standard.dictionary(forKey: intentDebugCountsKey) as? [String: [String: Int]] ?? [:]
  }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct AlarmSchedulerMetadata: AlarmMetadata {
  let alarmId: String
  let title: String
  let values: [String: AlarmSchedulerMetadataValue]
}

@available(iOS 26.0, *)
private struct AlarmSchedulerAlertPresentationResult {
  let alert: AlarmPresentation.Alert
  let debugState: [String: Any]
}

private enum AlarmSchedulerMetadataValue: Codable, Hashable, Sendable {
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

  init() {
    alarmId = ""
    behavior = "openApp"
    alarmTitle = "Alarm"
    hour = 0
    minute = 0
    weekdays = ""
    soundName = ""
  }

  init(alarmId: String, behavior: String, title: String, hour: Int, minute: Int, weekdays: [Int], soundName: String?) {
    self.alarmId = alarmId
    self.behavior = behavior
    self.alarmTitle = title
    self.hour = hour
    self.minute = minute
    self.weekdays = weekdays.map(String.init).joined(separator: ",")
    self.soundName = soundName ?? ""
  }

  func perform() async throws -> some IntentResult {
    let shouldReschedule = behavior == "rescheduleImmediate" && !AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId)
    var details: [String: Any] = [
      "foregroundRequested": true
    ]
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

  init() {
    alarmId = ""
  }

  init(alarmId: String) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    _ = AlarmSchedulerNativeAlarmStore.recordIntentHandoff(alarmId: alarmId, action: "secondaryOpen")
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

  init() {
    alarmId = ""
  }

  init(alarmId: String) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    _ = AlarmSchedulerNativeAlarmStore.recordIntentHandoff(alarmId: alarmId, action: "secondaryOpen")
    return .result()
  }
}

@available(iOS 26.0, *)
private struct AlarmSchedulerBackupScheduleResult {
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
private enum AlarmSchedulerRescheduler {
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
            soundName: soundName
          ),
          secondaryIntent: AlarmSchedulerSecondaryOpenIntent(alarmId: originalAlarmId),
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

public class AlarmSchedulerModule: Module {
  private var alarmActionObserver: NSObjectProtocol?
  private var alarmUpdatesTask: Task<Void, Never>?

  deinit {
    if let alarmActionObserver {
      NotificationCenter.default.removeObserver(alarmActionObserver)
    }
    alarmUpdatesTask?.cancel()
  }

  public func definition() -> ModuleDefinition {
    Name("AlarmScheduler")

    Events("onAlarmTriggered", "onAlarmAction", "onAlarmStateChange")

    AsyncFunction("getPermissionsAsync") { () async -> [String: Any] in
      return await self.permissions()
    }

    AsyncFunction("requestPermissionsAsync") { () async -> [String: Any] in
      #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        _ = try? await AlarmManager.shared.requestAuthorization()
      }
      #endif
      return await self.permissions()
    }

    AsyncFunction("openAlarmSettingsAsync") { () -> Bool in
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        return false
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url)
      }
      return true
    }.runOnQueue(.main)

    AsyncFunction("scheduleAlarmAsync") { (alarm: AlarmScheduleRecord) async throws -> [String: Any] in
      return try await self.schedule(alarm)
    }

    AsyncFunction("cancelAlarmAsync") { (id: String) async -> Bool in
      return await self.cancel(id: id)
    }

    AsyncFunction("getScheduledAlarmsAsync") { () -> [[String: Any]] in
      return self.storedAlarms()
    }

    AsyncFunction("getCurrentAlarmContextAsync") { () -> [String: Any]? in
      return self.currentAlarmContext()
    }

    AsyncFunction("getPendingAlarmActionsAsync") { () -> [[String: Any]] in
      return AlarmSchedulerNativeAlarmStore.all()
    }

    AsyncFunction("clearPendingAlarmActionsAsync") { (ids: [String]?) -> Void in
      AlarmSchedulerNativeAlarmStore.clear(ids: ids)
    }

    AsyncFunction("getPendingNativeAlarmHandoffAsync") { () -> [String: Any]? in
      return AlarmSchedulerNativeAlarmStore.pendingHandoff()
    }

    AsyncFunction("clearPendingNativeAlarmHandoffAsync") { () -> Void in
      AlarmSchedulerNativeAlarmStore.clearPendingHandoff()
    }

    AsyncFunction("completeNativeAlarmAsync") { (alarmId: String) async -> Void in
      AlarmSchedulerNativeAlarmStore.complete(alarmId: alarmId)
      await self.cancelNativeAndRetryAlarms(originalAlarmId: alarmId)
      AlarmSchedulerNativeAlarmStore.clearActions(alarmId: alarmId)
    }

    AsyncFunction("scheduleNativeAlarmBackupAsync") { (alarmId: String, delaySeconds: Double?) async -> [String: Any] in
      return await self.scheduleNativeAlarmBackup(alarmId: alarmId, delaySeconds: delaySeconds)
    }

    AsyncFunction("cancelNativeAlarmBackupAsync") { (alarmId: String) async -> Bool in
      return await self.cancelNativeAlarmBackup(alarmId: alarmId)
    }

    AsyncFunction("clearBypassAsync") { (alarmId: String) -> Void in
      AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: alarmId)
    }

    AsyncFunction("resetNativeAlarmCompletionAsync") { (alarmId: String) -> Void in
      AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: alarmId)
    }

    AsyncFunction("getNativeAlarmDebugStateAsync") { (alarmId: String) -> [String: Any] in
      var state: [String: Any] = [
        "alarmId": alarmId,
        "isComplete": AlarmSchedulerNativeAlarmStore.isComplete(alarmId: alarmId),
        "activeRetryAlarmIds": AlarmSchedulerNativeAlarmStore.retryAlarmIds(for: alarmId),
        "pendingActions": AlarmSchedulerNativeAlarmStore.all().filter { ($0["alarmId"] as? String) == alarmId },
        "pendingHandoff": AlarmSchedulerNativeAlarmStore.pendingHandoff() as Any,
        "intentDebugCounts": AlarmSchedulerNativeAlarmStore.intentDebugCounts(alarmId: alarmId),
        "currentContext": self.currentAlarmContext() as Any
      ]
      if let storedAlarm = self.storedAlarms().first(where: { ($0["id"] as? String) == alarmId }),
        let alarmKitDebugState = storedAlarm["alarmKitDebugState"] as? [String: Any] {
        alarmKitDebugState.forEach { key, value in
          state[key] = value
        }
      }
      return state
    }

    AsyncFunction("setSystemAlarmAsync") { (_: AlarmScheduleRecord) throws -> Bool in
      throw UnsupportedAlarmException("iOS does not expose the Clock app alarm list through a public API. Use scheduleAlarmAsync on iOS 26+.")
    }

    AsyncFunction("openSystemAlarmAppAsync") { () -> Bool in
      guard let url = URL(string: "clock-alarm:") else {
        return false
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url)
      }
      return true
    }.runOnQueue(.main)

    OnStartObserving("onAlarmAction") {
      self.startAlarmActionObserving()
    }

    OnStopObserving("onAlarmAction") {
      self.stopAlarmActionObserving()
    }

    OnStartObserving("onAlarmStateChange") {
      self.startAlarmUpdatesObserving()
    }

    OnStopObserving("onAlarmStateChange") {
      self.stopAlarmUpdatesObserving()
    }
  }

  private func startAlarmActionObserving() {
    guard alarmActionObserver == nil else {
      return
    }
    alarmActionObserver = NotificationCenter.default.addObserver(
      forName: AlarmSchedulerNativeAlarmStore.actionRecordedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let action = notification.userInfo as? [String: Any] else {
        return
      }
      self?.sendEvent("onAlarmAction", action)
    }
  }

  private func stopAlarmActionObserving() {
    if let alarmActionObserver {
      NotificationCenter.default.removeObserver(alarmActionObserver)
      self.alarmActionObserver = nil
    }
  }

  private func startAlarmUpdatesObserving() {
    guard alarmUpdatesTask == nil else {
      return
    }
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      alarmUpdatesTask = Task { [weak self] in
        for await alarms in AlarmManager.shared.alarmUpdates {
          guard !Task.isCancelled else {
            return
          }
          for alarm in alarms {
            await self?.sendAlarmStateChange(alarm)
          }
        }
      }
    }
    #endif
  }

  private func stopAlarmUpdatesObserving() {
    alarmUpdatesTask?.cancel()
    alarmUpdatesTask = nil
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  @MainActor
  private func sendAlarmStateChange(_ alarm: Alarm) {
    var event: [String: Any] = [
      "id": alarm.id.uuidString,
      "state": mapAlarmState(alarm.state),
      "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
    ]
    if let storedAlarm = storedAlarms().first(where: { ($0["id"] as? String) == alarm.id.uuidString }) {
      event["metadata"] = storedAlarm["metadata"]
    }
    sendEvent("onAlarmStateChange", event)
  }
  #endif

  private func permissions() async -> [String: Any] {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      let status = AlarmManager.shared.authorizationState
      return [
        "platform": "ios",
        "status": mapAuthorizationStatus(status),
        "canScheduleExactAlarms": status == .authorized,
        "canOpenSettings": true
      ]
    }
    #endif

    return [
      "platform": "ios",
      "status": "unavailable",
      "canScheduleExactAlarms": false,
      "canOpenSettings": true
    ]
  }

  private func schedule(_ alarm: AlarmScheduleRecord) async throws -> [String: Any] {
    let id = alarm.id?.isEmpty == false ? alarm.id! : UUID().uuidString
    AlarmSchedulerNativeAlarmStore.resetCompletion(alarmId: id)
    let hour = try requireHour(alarm.hour)
    let minute = try requireMinute(alarm.minute)
    let title = alarm.title?.isEmpty == false ? alarm.title! : "Alarm"
    let weekdays = try normalizeWeekdays(alarm.weekdays)
    let metadata = normalizeMetadata(alarm.ios?.metadata, id: id, title: title)
    let timestamp = alarm.timestamp.flatMap { $0 > Date().timeIntervalSince1970 * 1000 ? Int64($0) : nil }
      ?? nextTriggerTimestamp(hour: hour, minute: minute, weekdays: weekdays)
    let runtimeSoundUri = normalizedSoundName(alarm.ios?.soundUri) ?? normalizedSoundName(alarm.soundUri)
    let soundName: String?
    if let runtimeSoundUri {
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
        soundName: soundName
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
    save(alarm: stored)
    return stored
  }

  private func cancel(id: String) async -> Bool {
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
    let didRemoveStoredAlarm = remove(id: id)
    removeRuntimeSound(alarmId: id)
    return didCancelNativeAlarm || didRemoveStoredAlarm
  }

  private func cancelNativeAndRetryAlarms(originalAlarmId: String) async {
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

  private func scheduleNativeAlarmBackup(alarmId: String, delaySeconds: Double?) async -> [String: Any] {
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

  private func cancelNativeAlarmBackup(alarmId: String) async -> Bool {
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

  private func currentAlarmContext() -> [String: Any]? {
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
        return alarmContext(from: storedAlarm, state: mapAlarmState(alarm.state), nativeAlarmId: id)
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
    soundName: String?
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
    let countdownTitle = options?.countdownTitle?.isEmpty == false ? options!.countdownTitle! : nil
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
    let presentation = AlarmPresentation(
      alert: alertPresentation.alert,
      countdown: countdownTitle.map { AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: $0)) }
    )
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
    debugState["sound"] = effectiveSoundName == nil ? "default" : "named"
    if let effectiveSoundName {
      debugState["soundName"] = effectiveSoundName
    } else if soundName != nil {
      debugState["soundFallbackReason"] = "iosSimulatorCustomSoundUnsupported"
    }
    return debugState
  }

  @available(iOS 26.0, *)
  private func makeAlertPresentation(
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

  /// Normalizes to the canonical mode. `openMissionOnly` is the former name of `openAppOnly` and is
  /// still accepted, so an app that has not migrated does not quietly regain a stop button.
  @available(iOS 26.0, *)
  private func normalizeAlertActionMode(_ mode: String?) -> String {
    switch mode ?? "default" {
    case "openAppOnly", "openMissionOnly":
      return "openAppOnly"
    default:
      return "default"
    }
  }

  @available(iOS 26.0, *)
  private func normalizeStopIntentBehavior(_ behavior: String?) -> String {
    switch behavior ?? "recordOnly" {
    case "recordOnly", "openApp", "rescheduleImmediate":
      return behavior ?? "recordOnly"
    default:
      return "recordOnly"
    }
  }

  @available(iOS 26.0, *)
  private func normalizeSecondaryButtonBehaviorName(
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
  private func makeStopIntent(
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
  private func makeSecondaryIntent(id: String, behavior: String?) -> (any LiveActivityIntent)? {
    switch behavior ?? "openApp" {
    case "openApp":
      return AlarmSchedulerSecondaryOpenIntent(alarmId: id)
    case "recordOnly":
      return AlarmSchedulerSecondaryRecordIntent(alarmId: id)
    default:
      return nil
    }
  }

  @available(iOS 26.0, *)
  private func normalizeSecondaryButtonBehavior(
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

  private func normalizeMetadata(_ metadata: [String: Any]?, id: String, title: String) -> [String: Any] {
    var normalized: [String: Any] = [:]
    metadata?.forEach { key, value in
      guard !key.isEmpty else {
        return
      }
      if let value = value as? String {
        normalized[key] = value
      } else if let value = value as? Bool {
        normalized[key] = value
      } else if let value = value as? Int {
        normalized[key] = value
      } else if let value = value as? Double {
        normalized[key] = value
      } else if let value = value as? Float {
        normalized[key] = Double(value)
      } else if let value = value as? NSNumber {
        normalized[key] = value
      }
    }
    normalized["alarmId"] = id
    normalized["title"] = title
    return normalized
  }

  private func normalizedSoundName(_ soundName: String?) -> String? {
    guard let soundName = soundName?.trimmingCharacters(in: .whitespacesAndNewlines), !soundName.isEmpty else {
      return nil
    }
    return soundName
  }

  /**
   * AlarmKit resolves runtime sounds from Library/Sounds. Transcoding to a short PCM CAF makes
   * picker results such as MP3, M4A, WAV and AIFF conform to the system alert-sound contract.
   */
  private func prepareRuntimeSound(uri: String, alarmId: String) throws -> String {
    guard let alarmId = UUID(uuidString: alarmId)?.uuidString.lowercased() else {
      throw InvalidAlarmException("Alarm id must be a UUID string on iOS.")
    }
    guard let sourceUrl = URL(string: uri), sourceUrl.isFileURL else {
      throw InvalidAlarmException("ios.soundUri must be a readable local file URI.")
    }

    let isSecurityScoped = sourceUrl.startAccessingSecurityScopedResource()
    defer {
      if isSecurityScoped {
        sourceUrl.stopAccessingSecurityScopedResource()
      }
    }

    let fileManager = FileManager.default
    guard let libraryUrl = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      throw InvalidAlarmException("Unable to locate the app Library directory.")
    }
    let soundsUrl = libraryUrl.appendingPathComponent("Sounds", isDirectory: true)
    do {
      try fileManager.createDirectory(at: soundsUrl, withIntermediateDirectories: true)
    } catch {
      throw InvalidAlarmException("Unable to create Library/Sounds: \(error.localizedDescription)")
    }

    let fileName = "alarm-scheduler-\(alarmId).caf"
    let destinationUrl = soundsUrl.appendingPathComponent(fileName)
    let temporaryUrl = fileManager.temporaryDirectory
      .appendingPathComponent("alarm-scheduler-\(alarmId)-\(UUID().uuidString).caf")
    do {
      let input = try AVAudioFile(forReading: sourceUrl)
      let format = input.processingFormat
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw InvalidAlarmException("The selected file does not contain readable audio.")
      }
      let output = try AVAudioFile(forWriting: temporaryUrl, settings: format.settings)
      var remainingFrames = min(input.length, AVAudioFramePosition(format.sampleRate * 29))
      while remainingFrames > 0 {
        let frameCount = AVAudioFrameCount(min(remainingFrames, 4096))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
          throw InvalidAlarmException("Unable to allocate an audio conversion buffer.")
        }
        try input.read(into: buffer, frameCount: frameCount)
        guard buffer.frameLength > 0 else {
          break
        }
        try output.write(from: buffer)
        remainingFrames -= AVAudioFramePosition(buffer.frameLength)
      }
      guard input.length > 0 else {
        throw InvalidAlarmException("The selected audio file is empty.")
      }
      if fileManager.fileExists(atPath: destinationUrl.path) {
        _ = try fileManager.replaceItemAt(destinationUrl, withItemAt: temporaryUrl)
      } else {
        try fileManager.moveItem(at: temporaryUrl, to: destinationUrl)
      }
    } catch let error as InvalidAlarmException {
      try? fileManager.removeItem(at: temporaryUrl)
      throw error
    } catch {
      try? fileManager.removeItem(at: temporaryUrl)
      throw InvalidAlarmException("Unable to import the selected alarm sound: \(error.localizedDescription)")
    }
    return fileName
  }

  private func removeRuntimeSound(alarmId: String) {
    guard let alarmId = UUID(uuidString: alarmId)?.uuidString.lowercased(),
      let libraryUrl = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
      return
    }
    let soundsUrl = libraryUrl.appendingPathComponent("Sounds", isDirectory: true)
    let prefix = "alarm-scheduler-\(alarmId)."
    let files = (try? FileManager.default.contentsOfDirectory(
      at: soundsUrl,
      includingPropertiesForKeys: nil
    )) ?? []
    for file in files where file.lastPathComponent.hasPrefix(prefix) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  private func makeAlarmSound(_ soundName: String?) -> AlertConfiguration.AlertSound {
    guard let soundName = alarmSchedulerEffectiveSoundName(normalizedSoundName(soundName)) else {
      return .default
    }
    return .named(soundName)
  }
  #endif

  private func alarmContext(from alarm: [String: Any], state: String, nativeAlarmId: String? = nil) -> [String: Any]? {
    guard let id = alarm["id"] as? String else {
      return nil
    }
    var context: [String: Any] = [
      "id": id,
      "metadata": alarm["metadata"] as? [String: Any] ?? normalizeMetadata(nil, id: id, title: alarm["title"] as? String ?? "Alarm"),
      "state": state
    ]
    if let nativeAlarmId {
      context["nativeAlarmId"] = nativeAlarmId
    }
    return context
  }

  private func recentFiredAlarmContext(excluding activeIds: Set<String>) -> [String: Any]? {
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let recentWindowMillis: Int64 = 60 * 60 * 1000
    return storedAlarms()
      .filter { alarm in
        guard
          let id = alarm["id"] as? String,
          let timestamp = alarmTimestamp(alarm["timestamp"])
        else {
          return false
        }
        let weekdays = alarm["weekdays"] as? [Int] ?? []
        return weekdays.isEmpty &&
          !activeIds.contains(id) &&
          timestamp <= now &&
          now - timestamp <= recentWindowMillis
      }
      .sorted {
        (alarmTimestamp($0["timestamp"]) ?? 0) > (alarmTimestamp($1["timestamp"]) ?? 0)
      }
      .compactMap { alarmContext(from: $0, state: "alerting") }
      .first
  }

  private func alarmTimestamp(_ value: Any?) -> Int64? {
    if let value = value as? Int64 {
      return value
    }
    if let value = value as? Int {
      return Int64(value)
    }
    if let value = value as? Double {
      return Int64(value)
    }
    if let value = value as? NSNumber {
      return value.int64Value
    }
    return nil
  }

  private func nextTriggerTimestamp(hour: Int, minute: Int, weekdays: [Int]) -> Int64 {
    let calendar = Calendar.current
    let now = Date()
    for offset in 0..<14 {
      guard let day = calendar.date(byAdding: .day, value: offset, to: now) else {
        continue
      }
      var components = calendar.dateComponents([.year, .month, .day], from: day)
      components.hour = hour
      components.minute = minute
      components.second = 0
      guard let candidate = calendar.date(from: components), candidate > now else {
        continue
      }
      let weekday = isoWeekday(from: candidate)
      if weekdays.isEmpty || weekdays.contains(weekday) {
        return Int64(candidate.timeIntervalSince1970 * 1000)
      }
    }
    return Int64(now.addingTimeInterval(24 * 60 * 60).timeIntervalSince1970 * 1000)
  }

  private func isoWeekday(from date: Date) -> Int {
    let weekday = Calendar.current.component(.weekday, from: date)
    return weekday == 1 ? 7 : weekday - 1
  }

  private func storedAlarms() -> [[String: Any]] {
    let defaults = UserDefaults.standard
    guard let store = defaults.dictionary(forKey: "alarm_scheduler_store") as? [String: [String: Any]] else {
      return []
    }
    return Array(store.values)
  }

  private func save(alarm: [String: Any]) {
    var store = UserDefaults.standard.dictionary(forKey: "alarm_scheduler_store") as? [String: [String: Any]] ?? [:]
    if let id = alarm["id"] as? String {
      store[id] = alarm
      UserDefaults.standard.set(store, forKey: "alarm_scheduler_store")
    }
  }

  private func remove(id: String) -> Bool {
    var store = UserDefaults.standard.dictionary(forKey: "alarm_scheduler_store") as? [String: [String: Any]] ?? [:]
    let existed = store.removeValue(forKey: id) != nil
    UserDefaults.standard.set(store, forKey: "alarm_scheduler_store")
    return existed
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  private func mapAuthorizationStatus(_ status: AlarmManager.AuthorizationState) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unknown"
    }
  }

  @available(iOS 26.0, *)
  private func mapAlarmState(_ state: Alarm.State) -> String {
    switch state {
    case .scheduled:
      return "scheduled"
    case .alerting:
      return "alerting"
    case .countdown:
      return "countdown"
    case .paused:
      return "paused"
    @unknown default:
      return "scheduled"
    }
  }

  @available(iOS 26.0, *)
  private func alarmKitMetadataValues(_ metadata: [String: Any]) -> [String: AlarmSchedulerMetadataValue] {
    var values: [String: AlarmSchedulerMetadataValue] = [:]
    metadata.forEach { key, value in
      if let value = value as? String {
        values[key] = .string(value)
      } else if let value = value as? Bool {
        values[key] = .bool(value)
      } else if let value = value as? Int {
        values[key] = .number(Double(value))
      } else if let value = value as? Double {
        values[key] = .number(value)
      } else if let value = value as? Float {
        values[key] = .number(Double(value))
      } else if let value = value as? NSNumber {
        values[key] = .number(value.doubleValue)
      }
    }
    return values
  }
  #endif
}

private final class InvalidAlarmException: Exception {
  private let message: String

  override var reason: String {
    message
  }

  init(_ reason: String) {
    self.message = reason
    super.init()
  }
}

private final class UnsupportedAlarmException: Exception {
  private let message: String

  override var reason: String {
    message
  }

  init(_ reason: String) {
    self.message = reason
    super.init()
  }
}
