package expo.modules.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * AlarmManager forgets everything across a reboot, an app update, and a clock change. Without
 * this, every scheduled alarm silently disappears — the single biggest reliability gap between a
 * toy implementation and a real one.
 */
class AlarmSchedulerBootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    when (intent.action) {
      Intent.ACTION_BOOT_COMPLETED,
      Intent.ACTION_LOCKED_BOOT_COMPLETED,
      Intent.ACTION_MY_PACKAGE_REPLACED,
      Intent.ACTION_TIME_CHANGED,
      Intent.ACTION_TIMEZONE_CHANGED -> {
        val pendingResult = goAsync()
        try {
          AlarmSchedulerScheduler.rescheduleAll(context)
        } finally {
          pendingResult.finish()
        }
      }
      else -> Unit
    }
  }
}
