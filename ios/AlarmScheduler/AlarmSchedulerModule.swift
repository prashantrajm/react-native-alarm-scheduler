import ExpoModulesCore
import Foundation
import UIKit

#if canImport(AlarmKit)
import AlarmKit
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
      return self.visibleScheduledAlarms()
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
      self.finishOccurrenceRecords(alarmId: alarmId)
    }

    AsyncFunction("resolveAlarmOccurrenceAsync") { (occurrenceId: String, resolution: AlarmOccurrenceResolutionRecord) async throws -> [String: Any] in
      return try await self.resolveAlarmOccurrence(occurrenceId: occurrenceId, resolution: resolution)
    }

    AsyncFunction("getAlarmOccurrencesAsync") { (alarmId: String?) -> [[String: Any]] in
      return AlarmSchedulerOccurrenceStore.all(alarmId: alarmId)
    }

    AsyncFunction("cancelAlarmOccurrenceAsync") { (occurrenceId: String) async -> Bool in
      return await self.cancelAlarmOccurrence(occurrenceId: occurrenceId)
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
    let nativeAlarmId = alarm.id.uuidString
    var occurrence = AlarmSchedulerOccurrenceStore.occurrence(id: nativeAlarmId)
    let alarmId = occurrence?["alarmId"] as? String ?? nativeAlarmId
    let state = mapAlarmState(alarm.state)
    if state == "alerting",
      occurrence?["relationship"] as? String == "primary",
      occurrence?["occurrenceId"] as? String == alarmId {
      AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: alarmId, phase: "cancelled")
      occurrence = nil
    }
    if occurrence == nil,
      let storedAlarm = storedAlarms().first(where: { ($0["id"] as? String) == alarmId }) {
      if state == "alerting" {
        occurrence = activePrimaryOccurrence(
          alarmId: alarmId,
          metadata: storedAlarm["metadata"] as? [String: Any] ?? [:]
        )
      } else {
        occurrence = AlarmSchedulerOccurrenceStore.all(alarmId: alarmId).first(where: {
          ($0["relationship"] as? String) == "primary" &&
            (($0["phase"] as? String) == "scheduled" || ($0["phase"] as? String) == "ringing")
        })
      }
    } else if state == "alerting", let occurrenceId = occurrence?["occurrenceId"] as? String {
      AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: occurrenceId, phase: "ringing")
    }
    let occurrenceId = occurrence?["occurrenceId"] as? String ?? nativeAlarmId
    var event: [String: Any] = [
      "id": alarmId,
      "occurrenceId": occurrenceId,
      "state": state,
      "timestamp": Int64(Date().timeIntervalSince1970 * 1000)
    ]
    if let relationship = occurrence?["relationship"] {
      event["relationship"] = relationship
    }
    if let metadata = occurrence?["metadata"] {
      event["metadata"] = metadata
    } else if let storedAlarm = storedAlarms().first(where: { ($0["id"] as? String) == alarmId }) {
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
}
