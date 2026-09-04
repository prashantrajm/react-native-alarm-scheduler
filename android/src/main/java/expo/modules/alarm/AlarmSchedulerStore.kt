package expo.modules.alarm

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * SharedPreferences-backed mirror of the iOS `AlarmSchedulerNativeAlarmStore`.
 *
 * Every key name and record shape matches the iOS implementation so the JS layer
 * can treat both platforms identically. The store is read from three processes'
 * worth of entry points (module, broadcast receiver, foreground service) which all
 * live in the same process, so plain `apply()` writes are enough.
 */
internal object AlarmSchedulerStore {
  private const val PREFS_NAME = "alarm_scheduler_store"
  private const val ALARM_KEY_PREFIX = "alarm:"
  private const val KEY_ACTIONS = "alarm_scheduler_actions"
  private const val KEY_COMPLETIONS = "alarm_scheduler_completed_ids"
  private const val KEY_RETRY_IDS = "alarm_scheduler_retry_ids_by_alarm"
  private const val KEY_PENDING_HANDOFF = "alarm_scheduler_pending_handoff"
  private const val KEY_INTENT_DEBUG_COUNTS = "alarm_scheduler_intent_debug_counts"
  private const val KEY_ACTIVE_RING = "alarm_scheduler_active_ring"
  private const val KEY_MIGRATED = "alarm_scheduler_migrated_v2"

  private val reservedKeys = setOf(
    KEY_ACTIONS,
    KEY_COMPLETIONS,
    KEY_RETRY_IDS,
    KEY_PENDING_HANDOFF,
    KEY_INTENT_DEBUG_COUNTS,
    KEY_ACTIVE_RING,
    KEY_MIGRATED
  )

  private fun prefs(context: Context): SharedPreferences =
    context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  // region alarms

  fun saveAlarm(context: Context, alarm: JSONObject) {
    val id = alarm.optString("id").takeIf { it.isNotBlank() } ?: return
    prefs(context).edit().putString(ALARM_KEY_PREFIX + id, alarm.toString()).apply()
  }

  fun alarm(context: Context, id: String): JSONObject? {
    val prefs = prefs(context)
    val raw = prefs.getString(ALARM_KEY_PREFIX + id, null)
      ?: prefs.getString(id, null)
      ?: return null
    return runCatching { JSONObject(raw) }.getOrNull()
  }

  fun alarms(context: Context): List<JSONObject> {
    migrateLegacyKeysIfNeeded(context)
    return prefs(context).all.entries.mapNotNull { (key, value) ->
      if (!key.startsWith(ALARM_KEY_PREFIX)) {
        return@mapNotNull null
      }
      val raw = value as? String ?: return@mapNotNull null
      runCatching { JSONObject(raw) }.getOrNull()?.takeIf { it.has("id") && it.has("hour") }
    }
  }

  fun removeAlarm(context: Context, id: String): Boolean {
    val prefs = prefs(context)
    val existed = prefs.contains(ALARM_KEY_PREFIX + id) || prefs.contains(id)
    prefs.edit().remove(ALARM_KEY_PREFIX + id).remove(id).apply()
    return existed
  }

  /**
   * Alarms written by <= 0.1.7 used the bare alarm id as the preference key. Move them under
   * the `alarm:` prefix so bookkeeping keys can share the same preference file.
   */
  private fun migrateLegacyKeysIfNeeded(context: Context) {
    val prefs = prefs(context)
    if (prefs.getBoolean(KEY_MIGRATED, false)) {
      return
    }
    val editor = prefs.edit()
    prefs.all.forEach { (key, value) ->
      if (key.startsWith(ALARM_KEY_PREFIX) || reservedKeys.contains(key)) {
        return@forEach
      }
      val raw = value as? String ?: return@forEach
      val parsed = runCatching { JSONObject(raw) }.getOrNull() ?: return@forEach
      if (!parsed.has("id") || !parsed.has("hour")) {
        return@forEach
      }
      editor.putString(ALARM_KEY_PREFIX + parsed.getString("id"), raw)
      editor.remove(key)
    }
    editor.putBoolean(KEY_MIGRATED, true).apply()
  }

  // endregion

  // region actions

  fun actions(context: Context): List<JSONObject> {
    val raw = prefs(context).getString(KEY_ACTIONS, null) ?: return emptyList()
    val array = runCatching { JSONArray(raw) }.getOrNull() ?: return emptyList()
    return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
  }

  fun record(
    context: Context,
    alarmId: String,
    action: String,
    timestamp: Long = System.currentTimeMillis(),
    details: Map<String, Any?> = emptyMap()
  ): JSONObject {
    val event = JSONObject()
      .put("id", UUID.randomUUID().toString())
      .put("alarmId", alarmId)
      .put("action", action)
      .put("timestamp", timestamp)
    details.forEach { (key, value) ->
      if (value != null) {
        event.put(key, value)
      }
    }
    val array = JSONArray()
    actions(context).forEach(array::put)
    array.put(event)
    prefs(context).edit().putString(KEY_ACTIONS, array.toString()).apply()
    AlarmSchedulerEventBus.emitAction(event)
    return event
  }

  fun recordHandoff(
    context: Context,
    alarmId: String,
    action: String,
    timestamp: Long = System.currentTimeMillis(),
    details: Map<String, Any?> = emptyMap()
  ): JSONObject {
    incrementIntentInvocation(context, action, alarmId)
    val event = record(context, alarmId, action, timestamp, details)
    prefs(context).edit().putString(KEY_PENDING_HANDOFF, event.toString()).apply()
    return event
  }

  fun pendingHandoff(context: Context): JSONObject? {
    val raw = prefs(context).getString(KEY_PENDING_HANDOFF, null) ?: return null
    return runCatching { JSONObject(raw) }.getOrNull()
  }

  fun clearPendingHandoff(context: Context) {
    prefs(context).edit().remove(KEY_PENDING_HANDOFF).apply()
  }

  fun clearActions(context: Context, ids: List<String>?) {
    if (ids.isNullOrEmpty()) {
      prefs(context).edit().remove(KEY_ACTIONS).apply()
      return
    }
    val remaining = JSONArray()
    actions(context)
      .filter { !ids.contains(it.optString("id")) }
      .forEach(remaining::put)
    prefs(context).edit().putString(KEY_ACTIONS, remaining.toString()).apply()
  }

  fun clearActionsForAlarm(context: Context, alarmId: String) {
    val remaining = JSONArray()
    actions(context)
      .filter { it.optString("alarmId") != alarmId }
      .forEach(remaining::put)
    prefs(context).edit().putString(KEY_ACTIONS, remaining.toString()).apply()
    if (pendingHandoff(context)?.optString("alarmId") == alarmId) {
      clearPendingHandoff(context)
    }
  }

  // endregion

  // region completion

  fun complete(context: Context, alarmId: String) {
    val ids = completedAlarmIds(context).toMutableSet()
    ids.add(alarmId)
    prefs(context).edit().putStringSet(KEY_COMPLETIONS, ids).apply()
  }

  fun resetCompletion(context: Context, alarmId: String) {
    val ids = completedAlarmIds(context).toMutableSet()
    ids.remove(alarmId)
    prefs(context).edit().putStringSet(KEY_COMPLETIONS, ids).apply()
  }

  fun isComplete(context: Context, alarmId: String): Boolean = completedAlarmIds(context).contains(alarmId)

  private fun completedAlarmIds(context: Context): Set<String> =
    prefs(context).getStringSet(KEY_COMPLETIONS, emptySet())?.toSet() ?: emptySet()

  // endregion

  // region retry ids

  fun addRetryAlarmId(context: Context, retryAlarmId: String, alarmId: String) {
    val all = retryIdsByAlarmId(context)
    val ids = all.optJSONArray(alarmId) ?: JSONArray()
    val existing = (0 until ids.length()).map { ids.optString(it) }
    if (!existing.contains(retryAlarmId)) {
      ids.put(retryAlarmId)
    }
    all.put(alarmId, ids)
    prefs(context).edit().putString(KEY_RETRY_IDS, all.toString()).apply()
  }

  fun retryAlarmIds(context: Context, alarmId: String): List<String> {
    val ids = retryIdsByAlarmId(context).optJSONArray(alarmId) ?: return emptyList()
    return (0 until ids.length()).mapNotNull { ids.optString(it).takeIf(String::isNotBlank) }
  }

  fun clearRetryAlarmIds(context: Context, alarmId: String) {
    val all = retryIdsByAlarmId(context)
    all.remove(alarmId)
    prefs(context).edit().putString(KEY_RETRY_IDS, all.toString()).apply()
  }

  fun removeRetryAlarmId(context: Context, retryAlarmId: String, alarmId: String) {
    val all = retryIdsByAlarmId(context)
    val existing = all.optJSONArray(alarmId) ?: return
    val remaining = JSONArray()
    (0 until existing.length())
      .map { existing.optString(it) }
      .filter { it.isNotBlank() && it != retryAlarmId }
      .forEach(remaining::put)
    if (remaining.length() == 0) {
      all.remove(alarmId)
    } else {
      all.put(alarmId, remaining)
    }
    prefs(context).edit().putString(KEY_RETRY_IDS, all.toString()).apply()
  }

  private fun retryIdsByAlarmId(context: Context): JSONObject {
    val raw = prefs(context).getString(KEY_RETRY_IDS, null) ?: return JSONObject()
    return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
  }

  // endregion

  // region debug counters

  fun intentDebugCounts(context: Context, alarmId: String): Map<String, Any> {
    val counts = intentDebugCountsByAlarmId(context).optJSONObject(alarmId) ?: return emptyMap()
    return AlarmSchedulerJson.toMap(counts)
  }

  private fun incrementIntentInvocation(context: Context, action: String, alarmId: String) {
    val all = intentDebugCountsByAlarmId(context)
    val counts = all.optJSONObject(alarmId) ?: JSONObject()
    counts.put(action, counts.optInt(action, 0) + 1)
    all.put(alarmId, counts)
    prefs(context).edit().putString(KEY_INTENT_DEBUG_COUNTS, all.toString()).apply()
  }

  private fun intentDebugCountsByAlarmId(context: Context): JSONObject {
    val raw = prefs(context).getString(KEY_INTENT_DEBUG_COUNTS, null) ?: return JSONObject()
    return runCatching { JSONObject(raw) }.getOrDefault(JSONObject())
  }

  // endregion

  // region active ring session

  fun setActiveRingAlarmId(context: Context, alarmId: String?) {
    val editor = prefs(context).edit()
    if (alarmId == null) {
      editor.remove(KEY_ACTIVE_RING)
    } else {
      editor.putString(KEY_ACTIVE_RING, alarmId)
    }
    editor.apply()
  }

  fun activeRingAlarmId(context: Context): String? = prefs(context).getString(KEY_ACTIVE_RING, null)

  // endregion
}

internal object AlarmSchedulerJson {
  fun toMap(json: JSONObject?): Map<String, Any> {
    if (json == null) {
      return emptyMap()
    }
    val result = mutableMapOf<String, Any>()
    json.keys().forEach { key ->
      when (val value = json.opt(key)) {
        null, JSONObject.NULL -> Unit
        is JSONObject -> result[key] = toMap(value)
        is JSONArray -> result[key] = toList(value)
        else -> result[key] = value
      }
    }
    return result
  }

  fun toList(json: JSONArray?): List<Any> {
    if (json == null) {
      return emptyList()
    }
    return (0 until json.length()).mapNotNull { index ->
      when (val value = json.opt(index)) {
        null, JSONObject.NULL -> null
        is JSONObject -> toMap(value)
        is JSONArray -> toList(value)
        else -> value
      }
    }
  }

  fun fromMap(map: Map<String, Any?>?): JSONObject {
    val json = JSONObject()
    map?.forEach { (key, value) ->
      if (key.isBlank() || value == null) {
        return@forEach
      }
      when (value) {
        is String, is Boolean, is Int, is Long, is Double, is Float -> json.put(key, value)
        is Number -> json.put(key, value.toDouble())
        else -> Unit
      }
    }
    return json
  }

  fun intList(json: JSONArray?): List<Int> {
    if (json == null) {
      return emptyList()
    }
    return (0 until json.length()).map { json.optInt(it) }
  }

  fun fromIntList(values: List<Int>): JSONArray {
    val array = JSONArray()
    values.forEach(array::put)
    return array
  }
}
