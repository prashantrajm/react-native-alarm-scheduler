import Foundation

extension AlarmSchedulerModule {
  func cancelActiveOccurrenceRecords(alarmId: String) {
    AlarmSchedulerOccurrenceStore.all(alarmId: alarmId)
      .filter { ($0["phase"] as? String) == "scheduled" || ($0["phase"] as? String) == "ringing" }
      .forEach { occurrence in
        if let occurrenceId = occurrence["occurrenceId"] as? String {
          AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: occurrenceId, phase: "cancelled")
        }
      }
  }

  func finishOccurrenceRecords(alarmId: String) {
    AlarmSchedulerOccurrenceStore.all(alarmId: alarmId).forEach { occurrence in
      guard let occurrenceId = occurrence["occurrenceId"] as? String else {
        return
      }
      let phase = occurrence["phase"] as? String == "ringing" ? "completed" : "cancelled"
      AlarmSchedulerOccurrenceStore.updatePhase(occurrenceId: occurrenceId, phase: phase)
    }
  }

  func recordPrimaryOccurrence(
    alarmId: String,
    scheduledFor: Int64,
    metadata: [String: Any]
  ) {
    AlarmSchedulerOccurrenceStore.save([
      "occurrenceId": UUID(uuidString: alarmId)?.uuidString ?? alarmId,
      "alarmId": alarmId,
      "scheduledFor": scheduledFor,
      "relationship": "primary",
      "phase": "scheduled",
      "metadata": metadata
    ])
  }

  func visibleScheduledAlarms() -> [[String: Any]] {
    storedAlarms().filter { alarm in
      guard let alarmId = alarm["id"] as? String else {
        return false
      }
      let weekdays = alarm["weekdays"] as? [Int] ?? []
      let occurrences = AlarmSchedulerOccurrenceStore.all(alarmId: alarmId)
      return !weekdays.isEmpty || occurrences.isEmpty || occurrences.contains { occurrence in
        occurrence["relationship"] as? String == "primary" &&
          (occurrence["phase"] as? String == "scheduled" || occurrence["phase"] as? String == "ringing")
      }
    }
  }
}
