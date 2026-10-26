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

final class AlarmSchedulerRingHoldPolicyTests: XCTestCase {
  func testSecondsAreClampedAndDefaulted() {
    XCTAssertEqual(AlarmSchedulerRingHoldPolicy.seconds(nil), 30)
    XCTAssertEqual(AlarmSchedulerRingHoldPolicy.seconds(1), 5)
    XCTAssertEqual(AlarmSchedulerRingHoldPolicy.seconds(3600), 300)
    XCTAssertEqual(AlarmSchedulerRingHoldPolicy.seconds(.nan), 30)
    XCTAssertEqual(AlarmSchedulerRingHoldPolicy.seconds(42), 42)
  }

  func testLapsedOrCompletedHoldIsNotHeld() {
    XCTAssertTrue(AlarmSchedulerRingHoldPolicy.isHeld(heldUntil: 30_000, isComplete: false, now: 10_000))
    XCTAssertFalse(AlarmSchedulerRingHoldPolicy.isHeld(heldUntil: 30_000, isComplete: false, now: 30_000))
    XCTAssertFalse(AlarmSchedulerRingHoldPolicy.isHeld(heldUntil: 30_000, isComplete: true, now: 10_000))
    XCTAssertFalse(AlarmSchedulerRingHoldPolicy.isHeld(heldUntil: nil, isComplete: false, now: 10_000))
  }

  func testStaleRingingOccurrenceCannotBeHeld() {
    let hour: Int64 = 60 * 60 * 1000
    XCTAssertTrue(AlarmSchedulerRingHoldPolicy.isRecentlyRinging(scheduledFor: 0, now: hour))
    XCTAssertFalse(AlarmSchedulerRingHoldPolicy.isRecentlyRinging(scheduledFor: 0, now: hour + 1))
    XCTAssertFalse(AlarmSchedulerRingHoldPolicy.isRecentlyRinging(scheduledFor: hour, now: 0))
  }
}
