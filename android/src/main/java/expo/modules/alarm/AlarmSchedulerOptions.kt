package expo.modules.alarm

import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min

internal const val ALERT_ACTION_MODE_DEFAULT = "default"
internal const val ALERT_ACTION_MODE_OPEN_APP_ONLY = "openAppOnly"

internal const val STOP_BEHAVIOR_RECORD_ONLY = "recordOnly"
internal const val STOP_BEHAVIOR_OPEN_APP = "openApp"
internal const val STOP_BEHAVIOR_RESCHEDULE = "rescheduleImmediate"

internal const val FULL_SCREEN_TARGET_NATIVE = "native"
internal const val FULL_SCREEN_TARGET_APP = "app"

/**
 * Resolved, persisted per-alarm Android behaviour.
 *
 * Values are resolved once at schedule time and stored with the alarm so the broadcast receiver
 * and the ringing service never need the JS layer to be alive.
 *
 * Fields that mean the same thing on both platforms fall back to the `ios` options block when the
 * `android` block omits them. That is what lets an app written against the iOS/AlarmKit flow —
 * `ios.metadata`, `ios.alertActionMode: 'openAppOnly'`,
 * `ios.stopIntentBehavior: 'rescheduleImmediate'` — behave the same on Android with no JS changes.
 */
internal data class AlarmSchedulerOptions(
  val metadata: JSONObject,
  val alertTitle: String,
  val alertBody: String,
  val alertActionMode: String,
  val stopButtonTitle: String,
  val secondaryButtonTitle: String,
  val stopIntentBehavior: String,
  val secondaryButtonBehavior: String,
  val soundName: String?,
  val soundUri: String?,
  val vibrate: Boolean,
  val enforceVolume: Boolean,
  val restoreVolume: Boolean,
  val volume: Double,
  val fullScreen: Boolean,
  val fullScreenTarget: String,
  val launchUri: String?,
  val maxRingDurationSeconds: Double,
  val backupDelaySeconds: Double
) {
  fun toJson(): JSONObject = JSONObject()
    .put("metadata", metadata)
    .put("alertTitle", alertTitle)
    .put("alertBody", alertBody)
    .put("alertActionMode", alertActionMode)
    .put("stopButtonTitle", stopButtonTitle)
    .put("secondaryButtonTitle", secondaryButtonTitle)
    .put("stopIntentBehavior", stopIntentBehavior)
    .put("secondaryButtonBehavior", secondaryButtonBehavior)
    .put("soundName", soundName ?: JSONObject.NULL)
    .put("soundUri", soundUri ?: JSONObject.NULL)
    .put("vibrate", vibrate)
    .put("enforceVolume", enforceVolume)
    .put("restoreVolume", restoreVolume)
    .put("volume", volume)
    .put("fullScreen", fullScreen)
    .put("fullScreenTarget", fullScreenTarget)
    .put("launchUri", launchUri ?: JSONObject.NULL)
    .put("maxRingDurationSeconds", maxRingDurationSeconds)
    .put("backupDelaySeconds", backupDelaySeconds)

  companion object {
    const val DEFAULT_BACKUP_DELAY_SECONDS = 1.0
    const val DEFAULT_MAX_RING_DURATION_SECONDS = 300.0

    fun resolve(
      title: String,
      alarmId: String,
      soundUri: String?,
      android: AndroidAlarmOptionsRecord?,
      ios: IosAlarmOptionsRecord?
    ): AlarmSchedulerOptions {
      val metadata = AlarmSchedulerJson.fromMap(android?.metadata ?: ios?.metadata)
      metadata.put("alarmId", alarmId)
      metadata.put("title", title)

      val alertActionMode = normalizeAlertActionMode(android?.alertActionMode ?: ios?.alertActionMode)
      val secondaryButtonTitle = firstNonBlank(android?.secondaryButtonTitle, ios?.secondaryButtonTitle)
        ?: if (alertActionMode == ALERT_ACTION_MODE_OPEN_APP_ONLY) "Open app" else "Open"

      return AlarmSchedulerOptions(
        metadata = metadata,
        alertTitle = firstNonBlank(android?.alertTitle, ios?.alertTitle) ?: title,
        alertBody = firstNonBlank(android?.alertBody) ?: "Alarm",
        alertActionMode = alertActionMode,
        stopButtonTitle = firstNonBlank(android?.stopButtonTitle, ios?.stopButtonTitle) ?: "Stop",
        secondaryButtonTitle = secondaryButtonTitle,
        stopIntentBehavior = normalizeStopIntentBehavior(android?.stopIntentBehavior ?: ios?.stopIntentBehavior),
        secondaryButtonBehavior = normalizeSecondaryButtonBehavior(
          android?.secondaryButtonBehavior ?: ios?.secondaryButtonBehavior
        ),
        soundName = firstNonBlank(android?.soundName, ios?.soundName),
        soundUri = firstNonBlank(android?.soundUri, soundUri, ios?.soundUri),
        vibrate = android?.vibrate ?: true,
        enforceVolume = android?.enforceVolume ?: true,
        restoreVolume = android?.restoreVolume ?: true,
        volume = min(1.0, max(0.0, android?.volume ?: 1.0)),
        fullScreen = android?.fullScreen ?: true,
        fullScreenTarget = normalizeFullScreenTarget(android?.fullScreenTarget),
        launchUri = firstNonBlank(android?.launchUri),
        maxRingDurationSeconds = max(0.0, android?.maxRingDurationSeconds ?: DEFAULT_MAX_RING_DURATION_SECONDS),
        backupDelaySeconds = max(0.1, android?.backupDelaySeconds ?: DEFAULT_BACKUP_DELAY_SECONDS)
      )
    }

    fun fromJson(json: JSONObject?, title: String, alarmId: String): AlarmSchedulerOptions {
      if (json == null) {
        return resolve(title, alarmId, null, null, null)
      }
      val metadata = json.optJSONObject("metadata") ?: JSONObject()
      metadata.put("alarmId", alarmId)
      if (!metadata.has("title")) {
        metadata.put("title", title)
      }
      val alertActionMode = normalizeAlertActionMode(json.optStringOrNull("alertActionMode"))
      return AlarmSchedulerOptions(
        metadata = metadata,
        alertTitle = json.optStringOrNull("alertTitle") ?: title,
        alertBody = json.optStringOrNull("alertBody") ?: "Alarm",
        alertActionMode = alertActionMode,
        stopButtonTitle = json.optStringOrNull("stopButtonTitle") ?: "Stop",
        secondaryButtonTitle = json.optStringOrNull("secondaryButtonTitle")
          ?: if (alertActionMode == ALERT_ACTION_MODE_OPEN_APP_ONLY) "Open app" else "Open",
        stopIntentBehavior = normalizeStopIntentBehavior(json.optStringOrNull("stopIntentBehavior")),
        secondaryButtonBehavior = normalizeSecondaryButtonBehavior(json.optStringOrNull("secondaryButtonBehavior")),
        soundName = json.optStringOrNull("soundName"),
        soundUri = json.optStringOrNull("soundUri"),
        vibrate = json.optBoolean("vibrate", true),
        enforceVolume = json.optBoolean("enforceVolume", true),
        restoreVolume = json.optBoolean("restoreVolume", true),
        volume = min(1.0, max(0.0, json.optDouble("volume", 1.0))),
        fullScreen = json.optBoolean("fullScreen", true),
        fullScreenTarget = normalizeFullScreenTarget(json.optStringOrNull("fullScreenTarget")),
        launchUri = json.optStringOrNull("launchUri"),
        maxRingDurationSeconds = max(
          0.0,
          json.optDouble("maxRingDurationSeconds", DEFAULT_MAX_RING_DURATION_SECONDS)
        ),
        backupDelaySeconds = max(0.1, json.optDouble("backupDelaySeconds", DEFAULT_BACKUP_DELAY_SECONDS))
      )
    }

    private fun normalizeAlertActionMode(value: String?): String = when (value) {
      ALERT_ACTION_MODE_OPEN_APP_ONLY -> ALERT_ACTION_MODE_OPEN_APP_ONLY
      else -> ALERT_ACTION_MODE_DEFAULT
    }

    private fun normalizeStopIntentBehavior(value: String?): String = when (value) {
      STOP_BEHAVIOR_OPEN_APP, STOP_BEHAVIOR_RESCHEDULE -> value
      else -> STOP_BEHAVIOR_RECORD_ONLY
    }

    private fun normalizeSecondaryButtonBehavior(value: String?): String = when (value) {
      STOP_BEHAVIOR_RECORD_ONLY, "none" -> value
      else -> STOP_BEHAVIOR_OPEN_APP
    }

    private fun normalizeFullScreenTarget(value: String?): String = when (value) {
      FULL_SCREEN_TARGET_APP -> FULL_SCREEN_TARGET_APP
      else -> FULL_SCREEN_TARGET_NATIVE
    }

    private fun firstNonBlank(vararg values: String?): String? =
      values.firstOrNull { !it.isNullOrBlank() }?.trim()
  }
}

internal fun JSONObject.optStringOrNull(key: String): String? {
  if (!has(key) || isNull(key)) {
    return null
  }
  return optString(key).takeIf { it.isNotBlank() }
}
