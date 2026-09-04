import Foundation

enum AlarmSchedulerOccurrenceStore {
  private static let occurrencesKey = "alarm_scheduler_occurrences"
  private static let resolutionsKey = "alarm_scheduler_occurrence_resolutions"

  static func save(_ occurrence: [String: Any]) {
    guard let occurrenceId = occurrence["occurrenceId"] as? String, !occurrenceId.isEmpty else {
      return
    }
    var occurrences = storedOccurrences()
    occurrences[occurrenceId] = occurrence
    UserDefaults.standard.set(occurrences, forKey: occurrencesKey)
  }

  static func occurrence(id: String) -> [String: Any]? {
    storedOccurrences()[id]
  }

  static func all(alarmId: String? = nil) -> [[String: Any]] {
    storedOccurrences().values
      .filter { occurrence in
        alarmId == nil || occurrence["alarmId"] as? String == alarmId
      }
      .sorted { scheduledFor($0) > scheduledFor($1) }
  }

  static func updatePhase(occurrenceId: String, phase: String) {
    guard var occurrence = occurrence(id: occurrenceId) else {
      return
    }
    occurrence["phase"] = phase
    save(occurrence)
  }

  static func alarmId(for occurrenceId: String) -> String {
    occurrence(id: occurrenceId)?["alarmId"] as? String ?? occurrenceId
  }

  static func resolution(alarmId: String, idempotencyKey: String) -> [String: Any]? {
    storedResolutions()[resolutionKey(alarmId: alarmId, idempotencyKey: idempotencyKey)]
  }

  static func saveResolution(alarmId: String, idempotencyKey: String, result: [String: Any]) {
    var resolutions = storedResolutions()
    resolutions[resolutionKey(alarmId: alarmId, idempotencyKey: idempotencyKey)] = result
    UserDefaults.standard.set(resolutions, forKey: resolutionsKey)
  }

  private static func storedOccurrences() -> [String: [String: Any]] {
    UserDefaults.standard.dictionary(forKey: occurrencesKey) as? [String: [String: Any]] ?? [:]
  }

  private static func storedResolutions() -> [String: [String: Any]] {
    UserDefaults.standard.dictionary(forKey: resolutionsKey) as? [String: [String: Any]] ?? [:]
  }

  private static func resolutionKey(alarmId: String, idempotencyKey: String) -> String {
    "\(alarmId):\(idempotencyKey)"
  }

  private static func scheduledFor(_ occurrence: [String: Any]) -> Int64 {
    (occurrence["scheduledFor"] as? NSNumber)?.int64Value ?? 0
  }
}
