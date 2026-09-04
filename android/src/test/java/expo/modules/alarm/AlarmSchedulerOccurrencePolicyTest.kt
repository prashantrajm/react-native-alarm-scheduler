package expo.modules.alarm

import org.junit.Assert.assertNotEquals
import org.junit.Test

class AlarmSchedulerOccurrencePolicyTest {
  @Test
  fun repeatingPrimaryDeliveriesReceiveDistinctIds() {
    val alarmId = "42e5e5d0-17dd-4e0d-9712-12fb24b4ac54"
    val first = AlarmSchedulerOccurrencePolicy.newPrimaryOccurrenceId()
    val second = AlarmSchedulerOccurrencePolicy.newPrimaryOccurrenceId()

    assertNotEquals(alarmId, first)
    assertNotEquals(first, second)
  }

  @Test
  fun idempotencyIsScopedToOneDelivery() {
    val key = "complete"
    val first = AlarmSchedulerOccurrencePolicy.resolutionStorageKey("delivery-a", key)
    val second = AlarmSchedulerOccurrencePolicy.resolutionStorageKey("delivery-b", key)

    assertNotEquals(first, second)
  }
}
