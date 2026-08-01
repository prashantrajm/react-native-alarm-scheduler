package expo.modules.alarm

import org.json.JSONObject

/**
 * Bridges the broadcast receiver / foreground service back to the JS module when — and only
 * when — a React context happens to be alive. Everything emitted here is also persisted by
 * [ExpoAlarmStore], so a cold-launched app can replay the same information through
 * `getPendingNativeAlarmHandoffAsync()` / `getPendingAlarmActionsAsync()`.
 */
internal object ExpoAlarmEventBus {
  internal interface Listener {
    fun onAlarmTriggered(alarm: Map<String, Any>)
    fun onAlarmAction(action: Map<String, Any>)
    fun onAlarmStateChange(event: Map<String, Any>)
  }

  @Volatile
  private var listener: Listener? = null

  fun setListener(listener: Listener?) {
    this.listener = listener
  }

  /** Takes the already-serialized alarm so internal bookkeeping never leaks into the JS payload. */
  fun emitTriggered(alarm: Map<String, Any>) {
    listener?.onAlarmTriggered(alarm)
  }

  fun emitAction(action: JSONObject) {
    listener?.onAlarmAction(ExpoAlarmJson.toMap(action))
  }

  fun emitStateChange(alarmId: String, state: String, metadata: JSONObject?) {
    val event = JSONObject()
      .put("id", alarmId)
      .put("state", state)
      .put("timestamp", System.currentTimeMillis())
    if (metadata != null) {
      event.put("metadata", metadata)
    }
    listener?.onAlarmStateChange(ExpoAlarmJson.toMap(event))
  }
}
