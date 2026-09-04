import XCTest
@testable import AlarmScheduler

final class AlarmSchedulerOccurrencePolicyTests: XCTestCase {
  func testRepeatingPrimaryDeliveriesReceiveDistinctIds() {
    let alarmId = "42e5e5d0-17dd-4e0d-9712-12fb24b4ac54"
    let first = AlarmSchedulerOccurrencePolicy.newPrimaryOccurrenceId()
    let second = AlarmSchedulerOccurrencePolicy.newPrimaryOccurrenceId()

    XCTAssertNotEqual(alarmId, first)
    XCTAssertNotEqual(first, second)
  }

  func testIdempotencyIsScopedToOneDelivery() {
    let key = "complete"
    let first = AlarmSchedulerOccurrencePolicy.resolutionStorageKey(
      occurrenceId: "delivery-a",
      idempotencyKey: key
    )
    let second = AlarmSchedulerOccurrencePolicy.resolutionStorageKey(
      occurrenceId: "delivery-b",
      idempotencyKey: key
    )

    XCTAssertNotEqual(first, second)
  }

  func testResolvingPrimaryPreservesRepeatingSchedule() {
    XCTAssertTrue(AlarmSchedulerOccurrencePolicy.preservesPrimarySchedule(relationship: "primary"))
    XCTAssertFalse(AlarmSchedulerOccurrencePolicy.preservesPrimarySchedule(relationship: "followUp"))
  }
}
