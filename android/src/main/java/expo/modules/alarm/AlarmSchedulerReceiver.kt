package expo.modules.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmSchedulerReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != null && intent.action != AlarmSchedulerScheduler.ACTION_TRIGGERED) {
      return
    }
    // A throw here would crash the host app from a background broadcast. Whatever goes wrong,
    // failing quietly beats taking the app down with the alarm.
    runCatching { AlarmSchedulerScheduler.handleTriggered(context, intent) }
  }
}
