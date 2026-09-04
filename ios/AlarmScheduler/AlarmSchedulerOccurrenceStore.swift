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

  static func markRinging(occurrenceId: String) -> [String: Any]? {
    guard var occurrence = occurrence(id: occurrenceId) else {
      return nil
    }
    occurrence["phase"] = "ringing"
    save(occurrence)
    return occurrence
  }

  static func alarmId(for occurrenceId: String) -> String {
    occurrence(id: occurrenceId)?["alarmId"] as? String ?? occurrenceId
  }

  static func resolution(occurrenceId: String, idempotencyKey: String) -> [String: Any]? {
    storedResolutions()[resolutionKey(occurrenceId: occurrenceId, idempotencyKey: idempotencyKey)]
  }

  static func saveResolution(occurrenceId: String, idempotencyKey: String, result: [String: Any]) {
    var resolutions = storedResolutions()
    resolutions[resolutionKey(occurrenceId: occurrenceId, idempotencyKey: idempotencyKey)] = result
    UserDefaults.standard.set(resolutions, forKey: resolutionsKey)
  }

  static func activatePrimaryOccurrence(alarmId: String, metadata: [String: Any] = [:]) -> [String: Any] {
    if var occurrence = all(alarmId: alarmId).first(where: {
      ($0["relationship"] as? String) == "primary" &&
        (($0["phase"] as? String) == "scheduled" || ($0["phase"] as? String) == "ringing")
    }) {
      occurrence["phase"] = "ringing"
      save(occurrence)
      return occurrence
    }
    let definitionMetadata = metadata.isEmpty
      ? (all(alarmId: alarmId).first(where: { ($0["relationship"] as? String) == "primary" })?["metadata"] as? [String: Any] ?? [:])
      : metadata
    let occurrence: [String: Any] = [
      "occurrenceId": AlarmSchedulerOccurrencePolicy.newPrimaryOccurrenceId(),
      "alarmId": alarmId,
      "scheduledFor": Int64(Date().timeIntervalSince1970 * 1000),
      "relationship": "primary",
      "phase": "ringing",
      "metadata": definitionMetadata
    ]
    save(occurrence)
    return occurrence
  }

  private static func storedOccurrences() -> [String: [String: Any]] {
    UserDefaults.standard.dictionary(forKey: occurrencesKey) as? [String: [String: Any]] ?? [:]
  }

  private static func storedResolutions() -> [String: [String: Any]] {
    UserDefaults.standard.dictionary(forKey: resolutionsKey) as? [String: [String: Any]] ?? [:]
  }

  private static func resolutionKey(occurrenceId: String, idempotencyKey: String) -> String {
    AlarmSchedulerOccurrencePolicy.resolutionStorageKey(
      occurrenceId: occurrenceId,
      idempotencyKey: idempotencyKey
    )
  }

  private static func scheduledFor(_ occurrence: [String: Any]) -> Int64 {
    (occurrence["scheduledFor"] as? NSNumber)?.int64Value ?? 0
  }
}
