import ExpoModulesCore
import Foundation
import UIKit

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import SwiftUI
#endif

struct AlarmScheduleRecord: Record {
  @Field var id: String?
  @Field var hour: Int = -1
  @Field var minute: Int = -1
  @Field var title: String?
  @Field var weekdays: [Int]?
  @Field var timestamp: Double?
  @Field var showUi: Bool = false
  @Field var ios: IosAlarmOptionsRecord?
}

struct IosAlarmOptionsRecord: Record {
  @Field var metadata: [String: Any]?
  @Field var alertTitle: String?
  @Field var stopButtonTitle: String?
  @Field var secondaryButtonTitle: String?
  @Field var countdownTitle: String?
  @Field var stopIntentBehavior: String?
  @Field var secondaryButtonBehavior: String?
}

private enum ExpoAlarmActionStore {
  private static let actionsKey = "expo_alarm_actions"
  static let actionRecordedNotification = Notification.Name("expo.modules.alarm.actionRecorded")

  static func all() -> [[String: Any]] {
    UserDefaults.standard.array(forKey: actionsKey) as? [[String: Any]] ?? []
  }

  static func record(alarmId: String, action: String, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [String: Any] {
    let event: [String: Any] = [
      "id": UUID().uuidString,
      "alarmId": alarmId,
      "action": action,
      "timestamp": timestamp
    ]
    var actions = all()
    actions.append(event)
    UserDefaults.standard.set(actions, forKey: actionsKey)
    NotificationCenter.default.post(name: actionRecordedNotification, object: nil, userInfo: event)
    return event
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
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct ExpoAlarmMetadata: AlarmMetadata {
  let alarmId: String
  let title: String
  let values: [String: ExpoAlarmMetadataValue]
}

private enum ExpoAlarmMetadataValue: Codable, Hashable, Sendable {
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
private struct ExpoAlarmStopIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Stop Alarm"
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static var supportedModes: IntentModes = .background

  @Parameter(title: "Alarm ID")
  var alarmId: String

  init() {
    alarmId = ""
  }

  init(alarmId: String) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    _ = ExpoAlarmActionStore.record(alarmId: alarmId, action: "nativeStop")
    return .result()
  }
}

@available(iOS 26.0, *)
private struct ExpoAlarmSecondaryOpenIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Open Alarm"
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static var supportedModes: IntentModes = .foreground(.immediate)

  @Parameter(title: "Alarm ID")
  var alarmId: String

  init() {
    alarmId = ""
  }

  init(alarmId: String) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    _ = ExpoAlarmActionStore.record(alarmId: alarmId, action: "secondaryOpen")
    return .result()
  }
}

@available(iOS 26.0, *)
private struct ExpoAlarmSecondaryRecordIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Record Alarm Action"
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
  static var supportedModes: IntentModes = .background

  @Parameter(title: "Alarm ID")
  var alarmId: String

  init() {
    alarmId = ""
  }

  init(alarmId: String) {
    self.alarmId = alarmId
  }

  func perform() async throws -> some IntentResult {
    _ = ExpoAlarmActionStore.record(alarmId: alarmId, action: "secondaryOpen")
    return .result()
  }
}
#endif

public class ExpoAlarmModule: Module {
  private var alarmActionObserver: NSObjectProtocol?
  private var alarmUpdatesTask: Task<Void, Never>?

  deinit {
    if let alarmActionObserver {
      NotificationCenter.default.removeObserver(alarmActionObserver)
    }
    alarmUpdatesTask?.cancel()
  }

  public func definition() -> ModuleDefinition {
    Name("ExpoAlarm")

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
      return ExpoAlarmActionStore.all()
    }

    AsyncFunction("clearPendingAlarmActionsAsync") { (ids: [String]?) -> Void in
      ExpoAlarmActionStore.clear(ids: ids)
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
      forName: ExpoAlarmActionStore.actionRecordedNotification,
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
    let hour = try requireHour(alarm.hour)
    let minute = try requireMinute(alarm.minute)
    let title = alarm.title?.isEmpty == false ? alarm.title! : "Alarm"
    let weekdays = try normalizeWeekdays(alarm.weekdays)
    let metadata = normalizeMetadata(alarm.ios?.metadata, id: id, title: title)
    let timestamp = alarm.timestamp.flatMap { $0 > Date().timeIntervalSince1970 * 1000 ? Int64($0) : nil }
      ?? nextTriggerTimestamp(hour: hour, minute: minute, weekdays: weekdays)

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      try await scheduleAlarmKit(id: id, title: title, hour: hour, minute: minute, weekdays: weekdays, options: alarm.ios, metadata: metadata)
    } else {
      throw UnsupportedAlarmException("AlarmKit requires iOS 26 or newer.")
    }
    #else
    throw UnsupportedAlarmException("This build was compiled without AlarmKit. Build with the iOS 26 SDK or newer to schedule native iOS alarms.")
    #endif

    let stored: [String: Any] = [
      "id": id,
      "hour": hour,
      "minute": minute,
      "title": title,
      "weekdays": weekdays,
      "timestamp": timestamp,
      "platform": "ios",
      "metadata": metadata
    ]
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
    }
    #endif

    let didRemoveStoredAlarm = remove(id: id)
    return didCancelNativeAlarm || didRemoveStoredAlarm
  }

  private func currentAlarmContext() -> [String: Any]? {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      let activeAlarms = (try? AlarmManager.shared.alarms) ?? []
      let activeIds = Set(activeAlarms.map { $0.id.uuidString })
      let storedById = Dictionary(uniqueKeysWithValues: storedAlarms().compactMap { alarm -> (String, [String: Any])? in
        guard let id = alarm["id"] as? String else {
          return nil
        }
        return (id, alarm)
      })

      let activeContexts = activeAlarms.compactMap { alarm -> [String: Any]? in
        let id = alarm.id.uuidString
        guard let storedAlarm = storedById[id] else {
          return [
            "id": id,
            "metadata": normalizeMetadata(nil, id: id, title: "Alarm"),
            "state": mapAlarmState(alarm.state)
          ]
        }
        return alarmContext(from: storedAlarm, state: mapAlarmState(alarm.state))
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
    metadata: [String: Any]
  ) async throws {
    guard let alarmID = UUID(uuidString: id) else {
      throw InvalidAlarmException("Alarm id must be a UUID string on iOS.")
    }

    let alertTitle = options?.alertTitle?.isEmpty == false ? options!.alertTitle! : title
    let stopButtonTitle = options?.stopButtonTitle?.isEmpty == false ? options!.stopButtonTitle! : "Stop"
    let secondaryButtonTitle = options?.secondaryButtonTitle?.isEmpty == false ? options!.secondaryButtonTitle! : nil
    let countdownTitle = options?.countdownTitle?.isEmpty == false ? options!.countdownTitle! : nil
    let secondaryButtonBehavior = normalizeSecondaryButtonBehavior(options?.secondaryButtonBehavior, hasSecondaryButton: secondaryButtonTitle != nil)
    let secondaryButton = secondaryButtonTitle.map {
      AlarmButton(text: LocalizedStringResource(stringLiteral: $0), textColor: .white, systemImageName: "app.badge")
    }
    let alert = makeAlertPresentation(
      title: alertTitle,
      stopButtonTitle: stopButtonTitle,
      secondaryButton: secondaryButton,
      secondaryButtonBehavior: secondaryButtonBehavior
    )
    let presentation = AlarmPresentation(
      alert: alert,
      countdown: countdownTitle.map { AlarmPresentation.Countdown(title: LocalizedStringResource(stringLiteral: $0)) }
    )
    let attributes = AlarmAttributes(
      presentation: presentation,
      metadata: ExpoAlarmMetadata(alarmId: id, title: title, values: alarmKitMetadataValues(metadata)),
      tintColor: Color.accentColor
    )
    let schedule = try makeAlarmKitSchedule(hour: hour, minute: minute, weekdays: weekdays)
    let stopIntent = makeStopIntent(id: id, behavior: options?.stopIntentBehavior)
    let secondaryIntent = makeSecondaryIntent(id: id, behavior: options?.secondaryButtonBehavior)
    _ = try await AlarmManager.shared.schedule(
      id: alarmID,
      configuration: AlarmManager.AlarmConfiguration.alarm(
        schedule: schedule,
        attributes: attributes,
        stopIntent: stopIntent,
        secondaryIntent: secondaryIntent
      )
    )
  }

  @available(iOS 26.0, *)
  private func makeAlertPresentation(
    title: String,
    stopButtonTitle: String,
    secondaryButton: AlarmButton?,
    secondaryButtonBehavior: AlarmPresentation.Alert.SecondaryButtonBehavior?
  ) -> AlarmPresentation.Alert {
    if #available(iOS 26.1, *) {
      return AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        secondaryButton: secondaryButton,
        secondaryButtonBehavior: secondaryButtonBehavior
      )
    }
    return AlarmPresentation.Alert(
      title: LocalizedStringResource(stringLiteral: title),
      stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: stopButtonTitle), textColor: .white, systemImageName: "stop.fill"),
      secondaryButton: secondaryButton,
      secondaryButtonBehavior: secondaryButtonBehavior
    )
  }

  @available(iOS 26.0, *)
  private func makeStopIntent(id: String, behavior: String?) -> (any LiveActivityIntent)? {
    switch behavior ?? "recordOnly" {
    case "recordOnly":
      return ExpoAlarmStopIntent(alarmId: id)
    default:
      return nil
    }
  }

  @available(iOS 26.0, *)
  private func makeSecondaryIntent(id: String, behavior: String?) -> (any LiveActivityIntent)? {
    switch behavior ?? "openApp" {
    case "openApp":
      return ExpoAlarmSecondaryOpenIntent(alarmId: id)
    case "recordOnly":
      return ExpoAlarmSecondaryRecordIntent(alarmId: id)
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

  private func alarmContext(from alarm: [String: Any], state: String) -> [String: Any]? {
    guard let id = alarm["id"] as? String else {
      return nil
    }
    return [
      "id": id,
      "metadata": alarm["metadata"] as? [String: Any] ?? normalizeMetadata(nil, id: id, title: alarm["title"] as? String ?? "Alarm"),
      "state": state
    ]
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
    guard let store = defaults.dictionary(forKey: "expo_alarm_store") as? [String: [String: Any]] else {
      return []
    }
    return Array(store.values)
  }

  private func save(alarm: [String: Any]) {
    var store = UserDefaults.standard.dictionary(forKey: "expo_alarm_store") as? [String: [String: Any]] ?? [:]
    if let id = alarm["id"] as? String {
      store[id] = alarm
      UserDefaults.standard.set(store, forKey: "expo_alarm_store")
    }
  }

  private func remove(id: String) -> Bool {
    var store = UserDefaults.standard.dictionary(forKey: "expo_alarm_store") as? [String: [String: Any]] ?? [:]
    let existed = store.removeValue(forKey: id) != nil
    UserDefaults.standard.set(store, forKey: "expo_alarm_store")
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
  private func alarmKitMetadataValues(_ metadata: [String: Any]) -> [String: ExpoAlarmMetadataValue] {
    var values: [String: ExpoAlarmMetadataValue] = [:]
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
