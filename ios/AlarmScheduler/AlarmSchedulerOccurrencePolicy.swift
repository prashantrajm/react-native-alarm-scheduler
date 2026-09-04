import Foundation

enum AlarmSchedulerOccurrencePolicy {
  static func newPrimaryOccurrenceId() -> String {
    UUID().uuidString
  }

  static func resolutionStorageKey(occurrenceId: String, idempotencyKey: String) -> String {
    "\(occurrenceId):\(idempotencyKey)"
  }

  static func preservesPrimarySchedule(relationship: String?) -> Bool {
    relationship == "primary"
  }
}
