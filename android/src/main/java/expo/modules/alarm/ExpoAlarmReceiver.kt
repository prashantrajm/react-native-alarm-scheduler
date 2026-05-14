package expo.modules.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ExpoAlarmReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    ExpoAlarmScheduler.handleTriggered(context, intent)
  }
}
