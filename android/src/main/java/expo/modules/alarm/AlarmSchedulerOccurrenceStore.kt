package expo.modules.alarm

import android.content.Context
import org.json.JSONObject

internal object AlarmSchedulerOccurrenceStore {
  private const val PREFS_NAME = "alarm_scheduler_occurrences"
  private const val OCCURRENCE_PREFIX = "occurrence:"
  private const val RESOLUTION_PREFIX = "resolution:"

  private fun prefs(context: Context) =
    context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

  fun save(context: Context, occurrence: JSONObject) {
    val id = occurrence.optString("occurrenceId").takeIf(String::isNotBlank) ?: return
    prefs(context).edit().putString(OCCURRENCE_PREFIX + id, occurrence.toString()).apply()
  }

  fun occurrence(context: Context, occurrenceId: String): JSONObject? {
    val raw = prefs(context).getString(OCCURRENCE_PREFIX + occurrenceId, null) ?: return null
    return runCatching { JSONObject(raw) }.getOrNull()
  }

  fun all(context: Context, alarmId: String? = null): List<JSONObject> =
    prefs(context).all.mapNotNull { (key, value) ->
      if (!key.startsWith(OCCURRENCE_PREFIX)) return@mapNotNull null
      val occurrence = runCatching { JSONObject(value as? String ?: return@mapNotNull null) }.getOrNull()
        ?: return@mapNotNull null
      occurrence.takeIf { alarmId == null || it.optString("alarmId") == alarmId }
    }.sortedByDescending { it.optLong("scheduledFor") }

  fun updatePhase(context: Context, occurrenceId: String, phase: String) {
    val occurrence = occurrence(context, occurrenceId) ?: return
    occurrence.put("phase", phase)
    save(context, occurrence)
  }

  fun alarmId(context: Context, occurrenceId: String): String =
    occurrence(context, occurrenceId)?.optString("alarmId")?.takeIf(String::isNotBlank) ?: occurrenceId

  fun resolution(context: Context, alarmId: String, idempotencyKey: String): JSONObject? {
    val raw = prefs(context).getString(resolutionKey(alarmId, idempotencyKey), null) ?: return null
    return runCatching { JSONObject(raw) }.getOrNull()
  }

  fun saveResolution(context: Context, alarmId: String, idempotencyKey: String, result: JSONObject) {
    prefs(context).edit().putString(resolutionKey(alarmId, idempotencyKey), result.toString()).apply()
  }

  private fun resolutionKey(alarmId: String, idempotencyKey: String) =
    RESOLUTION_PREFIX + alarmId + ":" + idempotencyKey
}
