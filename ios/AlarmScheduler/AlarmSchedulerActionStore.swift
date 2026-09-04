import Foundation

enum AlarmSchedulerNativeAlarmStore {
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

  static func removeRetryAlarmId(_ retryAlarmId: String, for alarmId: String) {
    var allRetryIds = retryIdsByAlarmId()
    let remaining = (allRetryIds[alarmId] ?? []).filter { $0 != retryAlarmId }
    if remaining.isEmpty {
      allRetryIds.removeValue(forKey: alarmId)
    } else {
      allRetryIds[alarmId] = remaining
    }
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
