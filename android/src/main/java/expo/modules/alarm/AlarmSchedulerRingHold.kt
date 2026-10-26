package expo.modules.alarm

/** A ring quieted by `holdRingAsync`. Persisted so a restarted ring service keeps it. */
internal data class AlarmSchedulerRingHold(
  val alarmId: String,
  /** Epoch ms when the full ring resumes unless the hold is renewed. */
  val heldUntil: Long,
  /** Player level while held, 0–1 of the ring level. */
  val volume: Float,
  val vibrate: Boolean
)

/**
 * The pure rules behind a ring hold, kept free of Android types so they run as plain JVM tests.
 * Every path here errs towards a loud ring: anything stale, lapsed or completed is not a hold.
 */
internal object AlarmSchedulerRingHoldPolicy {
  const val DEFAULT_SECONDS = 30.0
  const val MIN_SECONDS = 5.0
  const val MAX_SECONDS = 300.0

  fun seconds(requested: Double?): Double =
    (requested?.takeIf { it.isFinite() } ?: DEFAULT_SECONDS).coerceIn(MIN_SECONDS, MAX_SECONDS)

  fun volume(requested: Double?): Float =
    (requested?.takeIf { it.isFinite() } ?: 0.0).coerceIn(0.0, 1.0).toFloat()

  /** A new hold, or the renewal of one: either way the timer restarts from [now]. */
  fun start(
    alarmId: String,
    seconds: Double?,
    volume: Double?,
    vibrate: Boolean?,
    now: Long
  ): AlarmSchedulerRingHold = AlarmSchedulerRingHold(
    alarmId = alarmId,
    heldUntil = now + (seconds(seconds) * 1000).toLong(),
    volume = volume(volume),
    vibrate = vibrate ?: false
  )

  /**
   * Milliseconds left on [hold] for [alarmId], or null when the ring must be loud: no hold, a hold
   * for another alarm, a completed alarm, or a hold that has already run out.
   */
  fun remainingMillis(hold: AlarmSchedulerRingHold?, alarmId: String, isComplete: Boolean, now: Long): Long? {
    if (hold == null || hold.alarmId != alarmId || isComplete) {
      return null
    }
    return (hold.heldUntil - now).takeIf { it > 0 }
  }
}
