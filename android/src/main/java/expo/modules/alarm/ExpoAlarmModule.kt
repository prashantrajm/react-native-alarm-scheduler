package expo.modules.alarm

import android.app.AlarmManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class AlarmScheduleRecord : Record {
  @Field var id: String? = null
  @Field var hour: Int = -1
  @Field var minute: Int = -1
  @Field var title: String? = null
  @Field var weekdays: List<Int>? = null
  @Field var timestamp: Double? = null
  @Field var showUi: Boolean = false
}

class ExpoAlarmModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ExpoAlarm")

    Events("onAlarmTriggered")

    AsyncFunction("getPermissionsAsync") {
      permissions()
    }

    AsyncFunction("requestPermissionsAsync") {
      val context = requireContext()
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !canScheduleExactAlarms()) {
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
          data = Uri.parse("package:${context.packageName}")
          addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
      }
      permissions()
    }

    AsyncFunction("openAlarmSettingsAsync") {
      val context = requireContext()
      val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
          data = Uri.parse("package:${context.packageName}")
        }
      } else {
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
          data = Uri.parse("package:${context.packageName}")
        }
      }
      intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
      true
    }

    AsyncFunction("scheduleAlarmAsync") { alarm: AlarmScheduleRecord ->
      ExpoAlarmScheduler.schedule(requireContext(), alarm)
    }

    AsyncFunction("cancelAlarmAsync") { id: String ->
      ExpoAlarmScheduler.cancel(requireContext(), id)
    }

    AsyncFunction("getScheduledAlarmsAsync") {
      ExpoAlarmScheduler.getAll(requireContext())
    }

    AsyncFunction("setSystemAlarmAsync") { alarm: AlarmScheduleRecord ->
      val context = requireContext()
      val hour = ExpoAlarmScheduler.requireHour(alarm.hour)
      val minute = ExpoAlarmScheduler.requireMinute(alarm.minute)
      val title = alarm.title?.takeIf { it.isNotBlank() } ?: "Alarm"
      val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
        putExtra(AlarmClock.EXTRA_HOUR, hour)
        putExtra(AlarmClock.EXTRA_MINUTES, minute)
        putExtra(AlarmClock.EXTRA_MESSAGE, title)
        putExtra(AlarmClock.EXTRA_SKIP_UI, !alarm.showUi)
        alarm.weekdays?.takeIf { it.isNotEmpty() }?.let { weekdays ->
          putIntegerArrayListExtra(AlarmClock.EXTRA_DAYS, ArrayList(weekdays.map(ExpoAlarmScheduler::toCalendarDay)))
        }
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }

      if (intent.resolveActivity(context.packageManager) == null) {
        false
      } else {
        context.startActivity(intent)
        true
      }
    }

    AsyncFunction("openSystemAlarmAppAsync") {
      val context = requireContext()
      val intent = Intent(AlarmClock.ACTION_SHOW_ALARMS).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      }

      if (intent.resolveActivity(context.packageManager) == null) {
        false
      } else {
        context.startActivity(intent)
        true
      }
    }
  }

  private fun requireContext() = appContext.reactContext
    ?: throw IllegalStateException("React context is not available.")

  private fun canScheduleExactAlarms(): Boolean {
    val alarmManager = requireContext().getSystemService(AlarmManager::class.java)
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
  }

  private fun permissions(): Map<String, Any> {
    val canSchedule = canScheduleExactAlarms()
    return mapOf(
      "platform" to "android",
      "status" to if (canSchedule) "authorized" else "denied",
      "canScheduleExactAlarms" to canSchedule,
      "canOpenSettings" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
    )
  }
}
