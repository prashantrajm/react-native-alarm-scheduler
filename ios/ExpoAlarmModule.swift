import ExpoModulesCore
import Foundation
import UIKit

#if canImport(AlarmKit)
import AlarmKit
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
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
private struct ExpoAlarmMetadata: AlarmMetadata {
  let title: String
}
#endif

public class ExpoAlarmModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ExpoAlarm")

    Events("onAlarmTriggered")

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
  }

  private func permissions() async -> [String: Any] {
    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      let status = await AlarmManager.shared.authorizationState
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
    let timestamp = alarm.timestamp.flatMap { $0 > Date().timeIntervalSince1970 * 1000 ? Int64($0) : nil }
      ?? nextTriggerTimestamp(hour: hour, minute: minute, weekdays: weekdays)

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      try await scheduleAlarmKit(id: id, title: title, hour: hour, minute: minute, weekdays: weekdays)
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
      "platform": "ios"
    ]
    save(alarm: stored)
    return stored
  }

  private func cancel(id: String) async -> Bool {
    var didCancelNativeAlarm = false

    #if canImport(AlarmKit)
    if #available(iOS 26.0, *) {
      if let uuid = UUID(uuidString: id) {
        try? await AlarmManager.shared.cancel(id: uuid)
        didCancelNativeAlarm = true
      }
    }
    #endif

    let didRemoveStoredAlarm = remove(id: id)
    return didCancelNativeAlarm || didRemoveStoredAlarm
  }

  #if canImport(AlarmKit)
  @available(iOS 26.0, *)
  private func scheduleAlarmKit(id: String, title: String, hour: Int, minute: Int, weekdays: [Int]) async throws {
    guard let alarmID = UUID(uuidString: id) else {
      throw InvalidAlarmException("Alarm id must be a UUID string on iOS.")
    }

    let presentation = AlarmPresentation(
      alert: AlarmPresentation.Alert(
        title: LocalizedStringResource(stringLiteral: title),
        stopButton: AlarmButton(text: LocalizedStringResource("Stop"), textColor: .white, systemImageName: "stop.fill")
      )
    )
    let attributes = AlarmAttributes(
      presentation: presentation,
      metadata: ExpoAlarmMetadata(title: title),
      tintColor: Color.accentColor
    )
    let schedule = try makeAlarmKitSchedule(hour: hour, minute: minute, weekdays: weekdays)
    _ = try await AlarmManager.shared.schedule(
      id: alarmID,
      configuration: AlarmManager.AlarmConfiguration(schedule: schedule, attributes: attributes)
    )
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
