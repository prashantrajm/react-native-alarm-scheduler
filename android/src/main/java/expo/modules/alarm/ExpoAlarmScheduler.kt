package expo.modules.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToLong

internal object ExpoAlarmScheduler {
  const val ACTION_TRIGGERED = "expo.modules.alarm.ALARM_TRIGGERED"
  const val EXTRA_ID = "expo.modules.alarm.extra.ID"
  const val EXTRA_IS_BACKUP = "expo.modules.alarm.extra.IS_BACKUP"
  const val EXTRA_BACKUP_ID = "expo.modules.alarm.extra.BACKUP_ID"

  private const val BACKUP_SUFFIX = "#backup"

  fun schedule(context: Context, alarm: AlarmScheduleRecord): Map<String, Any> {
    val id = alarm.id?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString()
    val hour = requireHour(alarm.hour)
    val minute = requireMinute(alarm.minute)
    val title = alarm.title?.takeIf { it.isNotBlank() } ?: "Alarm"
    val weekdays = normalizeWeekdays(alarm.weekdays)
    val options = ExpoAlarmOptions.resolve(title, id, alarm.android, alarm.ios)
    val triggerAtMillis = alarm.timestamp?.toLong()?.takeIf { it > System.currentTimeMillis() }
      ?: nextTriggerAtMillis(hour, minute, weekdays)

    // A freshly scheduled alarm is never "already completed".
    ExpoAlarmStore.resetCompletion(context, id)
    cancelBackups(context, id)

    val stored = JSONObject()
      .put("id", id)
      .put("hour", hour)
      .put("minute", minute)
      .put("title", title)
      .put("weekdays", ExpoAlarmJson.fromIntList(weekdays))
      .put("timestamp", triggerAtMillis)
      .put("platform", "android")
      .put("metadata", options.metadata)
      .put("options", options.toJson())

    ExpoAlarmStore.saveAlarm(context, stored)
    armExact(context, id, triggerAtMillis, isBackup = false, backupId = null)
    ExpoAlarmEventBus.emitStateChange(id, "scheduled", options.metadata)
    return serialize(stored)
  }

  fun cancel(context: Context, id: String): Boolean {
    val existing = ExpoAlarmStore.alarm(context, id)
    disarm(context, requestCode(id), triggerIntent(context, id, isBackup = false, backupId = null))
    cancelBackups(context, id)
    ExpoAlarmRingService.stopIfRinging(context, id)
    ExpoAlarmStore.resetCompletion(context, id)
    ExpoAlarmStore.clearActionsForAlarm(context, id)
    val removed = ExpoAlarmStore.removeAlarm(context, id)
    return existing != null || removed
  }

  fun getAll(context: Context): List<Map<String, Any>> = ExpoAlarmStore.alarms(context).map(::serialize)

  fun serialize(stored: JSONObject): Map<String, Any> {
    val result = mutableMapOf<String, Any>(
      "id" to stored.optString("id"),
      "hour" to stored.optInt("hour"),
      "minute" to stored.optInt("minute"),
      "title" to stored.optString("title", "Alarm"),
      "weekdays" to ExpoAlarmJson.intList(stored.optJSONArray("weekdays")),
      "timestamp" to stored.optLong("timestamp"),
      "platform" to "android"
    )
    stored.optJSONObject("metadata")?.let { result["metadata"] = ExpoAlarmJson.toMap(it) }
    return result
  }

  /**
   * Entry point for every alarm broadcast — primary occurrences and re-armed backups alike.
   */
  fun handleTriggered(context: Context, intent: Intent) {
    val id = intent.getStringExtra(EXTRA_ID) ?: return
    val isBackup = intent.getBooleanExtra(EXTRA_IS_BACKUP, false)
    val stored = ExpoAlarmStore.alarm(context, id)

    if (isBackup && ExpoAlarmStore.isComplete(context, id)) {
      // The mission finished between arming the backup and it firing. Stay quiet.
      cancelBackups(context, id)
      return
    }

    // The alarm was deleted while the broadcast was in flight.
    if (stored == null) {
      return
    }

    if (!isBackup) {
      ExpoAlarmStore.resetCompletion(context, id)
      rescheduleRepeatIfNeeded(context, stored)
    }

    val options = ExpoAlarmOptions.fromJson(
      stored.optJSONObject("options"),
      stored.optString("title", "Alarm"),
      id
    )

    // Persisted before anything that can fail, so however badly the presentation degrades, a
    // launched app can still find out which alarm fired and route to its own UI.
    ExpoAlarmStore.recordHandoff(
      context = context,
      alarmId = id,
      action = "secondaryOpen",
      details = mapOf("foregroundRequested" to true, "trigger" to true)
    )
    ExpoAlarmEventBus.emitTriggered(serialize(stored))
    ExpoAlarmStore.setActiveRingAlarmId(context, id)

    if (!ExpoAlarmRingService.start(context, id, isBackup)) {
      presentWithoutService(context, id, options)
    }
  }

  /**
   * The service could not be started. Ring through a notification channel and try the activity
   * directly — less reliable than the service, but far better than silence.
   */
  private fun presentWithoutService(context: Context, id: String, options: ExpoAlarmOptions) {
    ExpoAlarmNotifications.postFallbackNotification(context, id, options)
    if (!options.fullScreen) {
      return
    }
    val intent = if (options.fullScreenTarget == FULL_SCREEN_TARGET_APP) {
      ExpoAlarmNotifications.appIntent(context, id, options)
    } else {
      ExpoAlarmRingActivity.intent(context, id)
    } ?: return
    runCatching { context.startActivity(intent) }
  }

  fun rescheduleAll(context: Context) {
    val now = System.currentTimeMillis()
    ExpoAlarmStore.alarms(context).forEach { stored ->
      val id = stored.optString("id").takeIf { it.isNotBlank() } ?: return@forEach
      val weekdays = ExpoAlarmJson.intList(stored.optJSONArray("weekdays"))
      val timestamp = stored.optLong("timestamp")
      val triggerAtMillis = when {
        timestamp > now -> timestamp
        weekdays.isNotEmpty() -> nextTriggerAtMillis(stored.optInt("hour"), stored.optInt("minute"), weekdays)
        else -> {
          // A one-shot alarm whose time passed while the device was off is dropped, matching the
          // behaviour of the system Clock app.
          ExpoAlarmStore.removeAlarm(context, id)
          return@forEach
        }
      }
      stored.put("timestamp", triggerAtMillis)
      ExpoAlarmStore.saveAlarm(context, stored)
      armExact(context, id, triggerAtMillis, isBackup = false, backupId = null)
    }
  }

  private fun rescheduleRepeatIfNeeded(context: Context, stored: JSONObject) {
    val id = stored.optString("id")
    val weekdays = ExpoAlarmJson.intList(stored.optJSONArray("weekdays"))
    if (weekdays.isEmpty()) {
      return
    }
    val next = nextTriggerAtMillis(stored.optInt("hour"), stored.optInt("minute"), weekdays)
    stored.put("timestamp", next)
    ExpoAlarmStore.saveAlarm(context, stored)
    armExact(context, id, next, isBackup = false, backupId = null)
  }

  // region backups

  fun backupAlarmId(alarmId: String): String = alarmId + BACKUP_SUFFIX

  fun scheduleBackup(context: Context, alarmId: String, delaySeconds: Double?): Map<String, Any> {
    val stored = ExpoAlarmStore.alarm(context, alarmId)
    val options = ExpoAlarmOptions.fromJson(
      stored?.optJSONObject("options"),
      stored?.optString("title") ?: "Alarm",
      alarmId
    )
    val normalizedDelay = max(0.1, delaySeconds ?: options.backupDelaySeconds)
    val backupId = backupAlarmId(alarmId)

    if (stored == null || ExpoAlarmStore.isComplete(context, alarmId)) {
      return mapOf(
        "alarmId" to alarmId,
        "backupAlarmId" to backupId,
        "scheduled" to false,
        "delaySeconds" to normalizedDelay
      )
    }

    val scheduledFor = System.currentTimeMillis() + (normalizedDelay * 1000).roundToLong()
    val scheduled = armExact(context, alarmId, scheduledFor, isBackup = true, backupId = backupId)
    if (scheduled) {
      ExpoAlarmStore.addRetryAlarmId(context, backupId, alarmId)
    }

    val result = mutableMapOf<String, Any>(
      "alarmId" to alarmId,
      "backupAlarmId" to backupId,
      "scheduled" to scheduled,
      "delaySeconds" to normalizedDelay
    )
    if (scheduled) {
      result["scheduledFor"] = scheduledFor
    }
    return result
  }

  fun cancelBackups(context: Context, alarmId: String): Boolean {
    val backupId = backupAlarmId(alarmId)
    disarm(context, requestCode(backupId), triggerIntent(context, alarmId, isBackup = true, backupId = backupId))
    val hadRetries = ExpoAlarmStore.retryAlarmIds(context, alarmId).isNotEmpty()
    ExpoAlarmStore.clearRetryAlarmIds(context, alarmId)
    return hadRetries
  }

  // endregion

  // region alarm manager plumbing

  private fun armExact(
    context: Context,
    alarmId: String,
    triggerAtMillis: Long,
    isBackup: Boolean,
    backupId: String?
  ): Boolean {
    val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return false
    val code = requestCode(backupId ?: alarmId)
    val operation = PendingIntent.getBroadcast(
      context,
      code,
      triggerIntent(context, alarmId, isBackup, backupId),
      pendingFlags()
    )
    val showOperation = PendingIntent.getActivity(
      context,
      requestCode("show-${backupId ?: alarmId}"),
      launchIntent(context) ?: Intent(),
      pendingFlags()
    )

    return try {
      // setAlarmClock is the only Android API that survives Doze/App Standby *and* grants the
      // background activity-start allowance the ringing screen depends on.
      alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, showOperation), operation)
      true
    } catch (_: SecurityException) {
      // Exact alarms revoked by the user. Degrade instead of silently never ringing.
      try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
        } else {
          alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAtMillis, operation)
        }
        true
      } catch (_: Exception) {
        false
      }
    }
  }

  private fun disarm(context: Context, code: Int, intent: Intent) {
    val alarmManager = context.getSystemService(AlarmManager::class.java) ?: return
    val operation = PendingIntent.getBroadcast(context, code, intent, pendingFlags())
    alarmManager.cancel(operation)
    operation.cancel()
  }

  private fun triggerIntent(context: Context, alarmId: String, isBackup: Boolean, backupId: String?): Intent {
    return Intent(context, ExpoAlarmReceiver::class.java).apply {
      action = ACTION_TRIGGERED
      // PendingIntent.filterEquals() ignores extras, so the discriminating id goes in the data URI
      // to keep the primary and the backup PendingIntents distinct.
      data = Uri.parse("expo-alarm://${backupId ?: alarmId}")
      putExtra(EXTRA_ID, alarmId)
      putExtra(EXTRA_IS_BACKUP, isBackup)
      if (backupId != null) {
        putExtra(EXTRA_BACKUP_ID, backupId)
      }
    }
  }

  fun launchIntent(context: Context): Intent? =
    context.packageManager.getLaunchIntentForPackage(context.packageName)
      ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

  fun requestCode(value: String): Int = abs(value.hashCode())

  fun pendingFlags(): Int {
    return PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
  }

  // endregion

  // region validation + time math

  fun requireHour(hour: Int): Int {
    require(hour in 0..23) { "hour must be between 0 and 23." }
    return hour
  }

  fun requireMinute(minute: Int): Int {
    require(minute in 0..59) { "minute must be between 0 and 59." }
    return minute
  }

  fun toCalendarDay(weekday: Int): Int {
    return when (weekday) {
      1 -> Calendar.MONDAY
      2 -> Calendar.TUESDAY
      3 -> Calendar.WEDNESDAY
      4 -> Calendar.THURSDAY
      5 -> Calendar.FRIDAY
      6 -> Calendar.SATURDAY
      7 -> Calendar.SUNDAY
      else -> throw IllegalArgumentException("weekdays must use 1=Monday through 7=Sunday.")
    }
  }

  fun normalizeWeekdays(weekdays: List<Int>?): List<Int> {
    return weekdays.orEmpty().distinct().sorted().onEach(::toCalendarDay)
  }

  fun nextTriggerAtMillis(hour: Int, minute: Int, weekdays: List<Int>): Long {
    val now = Calendar.getInstance()
    val range = if (weekdays.isEmpty()) 8 else 14
    return List(range) { offset -> offset }
      .map { offset ->
        Calendar.getInstance().apply {
          add(Calendar.DAY_OF_YEAR, offset)
          set(Calendar.HOUR_OF_DAY, hour)
          set(Calendar.MINUTE, minute)
          set(Calendar.SECOND, 0)
          set(Calendar.MILLISECOND, 0)
        }
      }
      .filter { candidate ->
        candidate.timeInMillis > now.timeInMillis &&
          (weekdays.isEmpty() || weekdays.contains(fromCalendarDay(candidate.get(Calendar.DAY_OF_WEEK))))
      }
      .minByOrNull { it.timeInMillis }
      ?.timeInMillis
      ?: throw IllegalArgumentException("Unable to calculate the next alarm time.")
  }

  private fun fromCalendarDay(calendarDay: Int): Int {
    return when (calendarDay) {
      Calendar.MONDAY -> 1
      Calendar.TUESDAY -> 2
      Calendar.WEDNESDAY -> 3
      Calendar.THURSDAY -> 4
      Calendar.FRIDAY -> 5
      Calendar.SATURDAY -> 6
      Calendar.SUNDAY -> 7
      else -> 1
    }
  }

  // endregion
}
