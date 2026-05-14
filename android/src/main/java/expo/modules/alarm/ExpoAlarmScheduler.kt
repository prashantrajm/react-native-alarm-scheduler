package expo.modules.alarm

import android.Manifest
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar
import java.util.UUID
import kotlin.math.abs

internal object ExpoAlarmScheduler {
  private const val PREFS_NAME = "expo_alarm_store"
  private const val CHANNEL_ID = "expo_alarm_alerts"
  private const val EXTRA_ID = "expo.modules.alarm.extra.ID"
  private const val EXTRA_TITLE = "expo.modules.alarm.extra.TITLE"
  private const val EXTRA_HOUR = "expo.modules.alarm.extra.HOUR"
  private const val EXTRA_MINUTE = "expo.modules.alarm.extra.MINUTE"
  private const val EXTRA_WEEKDAYS = "expo.modules.alarm.extra.WEEKDAYS"

  fun schedule(context: Context, alarm: AlarmScheduleRecord): Map<String, Any> {
    val id = alarm.id?.takeIf { it.isNotBlank() } ?: UUID.randomUUID().toString()
    val hour = requireHour(alarm.hour)
    val minute = requireMinute(alarm.minute)
    val title = alarm.title?.takeIf { it.isNotBlank() } ?: "Alarm"
    val weekdays = normalizeWeekdays(alarm.weekdays)
    val triggerAtMillis = alarm.timestamp?.toLong()?.takeIf { it > System.currentTimeMillis() }
      ?: nextTriggerAtMillis(hour, minute, weekdays)

    scheduleInternal(context, id, title, hour, minute, weekdays, triggerAtMillis)

    val serialized = mapOf(
      "id" to id,
      "hour" to hour,
      "minute" to minute,
      "title" to title,
      "weekdays" to weekdays,
      "timestamp" to triggerAtMillis,
      "platform" to "android"
    )
    save(context, serialized)
    return serialized
  }

  fun cancel(context: Context, id: String): Boolean {
    val alarm = getAll(context).firstOrNull { it["id"] == id } ?: return false
    val intent = receiverIntent(
      context,
      id,
      alarm["title"] as? String ?: "Alarm",
      alarm["hour"] as? Int ?: 0,
      alarm["minute"] as? Int ?: 0,
      alarm["weekdays"] as? List<Int> ?: emptyList()
    )
    val pendingIntent = PendingIntent.getBroadcast(context, requestCode(id), intent, pendingFlags())
    context.getSystemService(AlarmManager::class.java).cancel(pendingIntent)
    remove(context, id)
    return true
  }

  fun getAll(context: Context): List<Map<String, Any>> {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    return prefs.all.values.mapNotNull { value ->
      val json = value as? String ?: return@mapNotNull null
      runCatching {
        val obj = JSONObject(json)
        val weekdays = obj.optJSONArray("weekdays") ?: JSONArray()
        mapOf(
          "id" to obj.getString("id"),
          "hour" to obj.getInt("hour"),
          "minute" to obj.getInt("minute"),
          "title" to obj.getString("title"),
          "weekdays" to List(weekdays.length()) { index -> weekdays.getInt(index) },
          "timestamp" to obj.getLong("timestamp"),
          "platform" to "android"
        )
      }.getOrNull()
    }
  }

  fun handleTriggered(context: Context, intent: Intent) {
    val id = intent.getStringExtra(EXTRA_ID) ?: return
    val title = intent.getStringExtra(EXTRA_TITLE) ?: "Alarm"
    val hour = intent.getIntExtra(EXTRA_HOUR, 0)
    val minute = intent.getIntExtra(EXTRA_MINUTE, 0)
    val weekdays = intent.getIntegerArrayListExtra(EXTRA_WEEKDAYS)?.toList() ?: emptyList()

    showNotification(context, id, title)

    if (weekdays.isEmpty()) {
      remove(context, id)
    } else {
      val nextTriggerAtMillis = nextTriggerAtMillis(hour, minute, weekdays)
      scheduleInternal(context, id, title, hour, minute, weekdays, nextTriggerAtMillis)
      save(context, mapOf(
        "id" to id,
        "hour" to hour,
        "minute" to minute,
        "title" to title,
        "weekdays" to weekdays,
        "timestamp" to nextTriggerAtMillis,
        "platform" to "android"
      ))
    }
  }

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

  private fun scheduleInternal(
    context: Context,
    id: String,
    title: String,
    hour: Int,
    minute: Int,
    weekdays: List<Int>,
    triggerAtMillis: Long
  ) {
    val alarmManager = context.getSystemService(AlarmManager::class.java)
    val operation = PendingIntent.getBroadcast(
      context,
      requestCode(id),
      receiverIntent(context, id, title, hour, minute, weekdays),
      pendingFlags()
    )
    val showIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
      ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    val showOperation = PendingIntent.getActivity(
      context,
      requestCode("show-$id"),
      showIntent ?: Intent(),
      pendingFlags()
    )
    alarmManager.setAlarmClock(AlarmManager.AlarmClockInfo(triggerAtMillis, showOperation), operation)
  }

  private fun receiverIntent(
    context: Context,
    id: String,
    title: String,
    hour: Int,
    minute: Int,
    weekdays: List<Int>
  ): Intent {
    return Intent(context, ExpoAlarmReceiver::class.java).apply {
      action = "expo.modules.alarm.ALARM_TRIGGERED"
      putExtra(EXTRA_ID, id)
      putExtra(EXTRA_TITLE, title)
      putExtra(EXTRA_HOUR, hour)
      putExtra(EXTRA_MINUTE, minute)
      putIntegerArrayListExtra(EXTRA_WEEKDAYS, ArrayList(weekdays))
    }
  }

  private fun nextTriggerAtMillis(hour: Int, minute: Int, weekdays: List<Int>): Long {
    val now = Calendar.getInstance()
    val candidates = if (weekdays.isEmpty()) {
      List(8) { offset -> offset }
    } else {
      List(14) { offset -> offset }
    }.map { offset ->
      Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, offset)
        set(Calendar.HOUR_OF_DAY, hour)
        set(Calendar.MINUTE, minute)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
      }
    }.filter { candidate ->
      candidate.timeInMillis > now.timeInMillis &&
        (weekdays.isEmpty() || weekdays.contains(fromCalendarDay(candidate.get(Calendar.DAY_OF_WEEK))))
    }

    return candidates.minByOrNull { it.timeInMillis }?.timeInMillis
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

  private fun normalizeWeekdays(weekdays: List<Int>?): List<Int> {
    return weekdays.orEmpty().distinct().sorted().onEach(::toCalendarDay)
  }

  private fun save(context: Context, alarm: Map<String, Any>) {
    val id = alarm["id"] as String
    val weekdays = JSONArray(alarm["weekdays"] as List<*>)
    val obj = JSONObject()
      .put("id", id)
      .put("hour", alarm["hour"])
      .put("minute", alarm["minute"])
      .put("title", alarm["title"])
      .put("weekdays", weekdays)
      .put("timestamp", alarm["timestamp"])
      .put("platform", "android")
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      .edit()
      .putString(id, obj.toString())
      .apply()
  }

  private fun remove(context: Context, id: String) {
    context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      .edit()
      .remove(id)
      .apply()
  }

  private fun showNotification(context: Context, id: String, title: String) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
      context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
    ) {
      return
    }

    val notificationManager = context.getSystemService(NotificationManager::class.java)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
      val channel = NotificationChannel(CHANNEL_ID, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
        setSound(soundUri, AudioAttributes.Builder()
          .setUsage(AudioAttributes.USAGE_ALARM)
          .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
          .build())
        enableVibration(true)
      }
      notificationManager.createNotificationChannel(channel)
    }

    val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
    val pendingIntent = PendingIntent.getActivity(
      context,
      requestCode("notification-$id"),
      openIntent ?: Intent(),
      pendingFlags()
    )

    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(context, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(context)
    }

    val notification = builder
      .setSmallIcon(context.applicationInfo.icon)
      .setContentTitle(title)
      .setContentText("Alarm")
      .setCategory(Notification.CATEGORY_ALARM)
      .setPriority(Notification.PRIORITY_MAX)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .setAutoCancel(true)
      .setContentIntent(pendingIntent)
      .build()

    notificationManager.notify(requestCode(id), notification)
  }

  private fun requestCode(value: String): Int = abs(value.hashCode())

  private fun pendingFlags(): Int {
    return PendingIntent.FLAG_UPDATE_CURRENT or
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
  }
}
