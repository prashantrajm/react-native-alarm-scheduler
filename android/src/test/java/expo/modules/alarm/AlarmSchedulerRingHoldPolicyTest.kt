package expo.modules.alarm

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class AlarmSchedulerRingHoldPolicyTest {
  private val alarmId = "42e5e5d0-17dd-4e0d-9712-12fb24b4ac54"

  @Test
  fun secondsAreClampedAndDefaulted() {
    assertEquals(30.0, AlarmSchedulerRingHoldPolicy.seconds(null), 0.0)
    assertEquals(5.0, AlarmSchedulerRingHoldPolicy.seconds(1.0), 0.0)
    assertEquals(300.0, AlarmSchedulerRingHoldPolicy.seconds(3600.0), 0.0)
    assertEquals(30.0, AlarmSchedulerRingHoldPolicy.seconds(Double.NaN), 0.0)
    assertEquals(42.0, AlarmSchedulerRingHoldPolicy.seconds(42.0), 0.0)
  }

  @Test
  fun holdDefaultsToMutedWithoutVibration() {
    val hold = AlarmSchedulerRingHoldPolicy.start(alarmId, null, null, null, now = 1_000)

    assertEquals(31_000, hold.heldUntil)
    assertEquals(0f, hold.volume, 0f)
    assertFalse(hold.vibrate)
    assertEquals(1f, AlarmSchedulerRingHoldPolicy.volume(4.0), 0f)
  }

  @Test
  fun renewingRestartsTheTimer() {
    val first = AlarmSchedulerRingHoldPolicy.start(alarmId, 30.0, null, null, now = 0)
    val renewed = AlarmSchedulerRingHoldPolicy.start(alarmId, 30.0, null, null, now = 10_000)

    assertEquals(30_000, first.heldUntil)
    assertEquals(40_000, renewed.heldUntil)
    assertEquals(30_000L, AlarmSchedulerRingHoldPolicy.remainingMillis(renewed, alarmId, false, now = 10_000))
  }

  @Test
  fun persistedHoldIsReappliedForTheRemainingTime() {
    val hold = AlarmSchedulerRingHoldPolicy.start(alarmId, 30.0, null, null, now = 0)

    assertEquals(18_000L, AlarmSchedulerRingHoldPolicy.remainingMillis(hold, alarmId, false, now = 12_000))
  }

  @Test
  fun anythingStaleRingsLoud() {
    val hold = AlarmSchedulerRingHoldPolicy.start(alarmId, 30.0, null, null, now = 0)

    assertNull(AlarmSchedulerRingHoldPolicy.remainingMillis(null, alarmId, false, now = 0))
    assertNull(AlarmSchedulerRingHoldPolicy.remainingMillis(hold, "other-alarm", false, now = 0))
    assertNull(AlarmSchedulerRingHoldPolicy.remainingMillis(hold, alarmId, false, now = 30_000))
  }

  @Test
  fun noResumeOrHoldAfterCompletion() {
    val hold = AlarmSchedulerRingHoldPolicy.start(alarmId, 30.0, null, null, now = 0)

    assertNull(AlarmSchedulerRingHoldPolicy.remainingMillis(hold, alarmId, isComplete = true, now = 1_000))
  }
}
