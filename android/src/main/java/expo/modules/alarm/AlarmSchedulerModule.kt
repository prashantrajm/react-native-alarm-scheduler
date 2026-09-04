package expo.modules.alarm

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.AlarmClock
import android.provider.Settings
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record
import org.json.JSONObject

class AlarmScheduleRecord : Record {
  @Field var id: String? = null
  @Field var hour: Int = -1
  @Field var minute: Int = -1
  @Field var title: String? = null
  @Field var weekdays: List<Int>? = null
  @Field var timestamp: Double? = null
  @Field var showUi: Boolean = false
  @Field var soundUri: String? = null
  @Field var ios: IosAlarmOptionsRecord? = null
  @Field var android: AndroidAlarmOptionsRecord? = null
}

class IosAlarmOptionsRecord : Record {
  @Field var metadata: Map<String, Any>? = null
  @Field var alertTitle: String? = null
  @Field var alertActionMode: String? = null
  @Field var stopButtonTitle: String? = null
  @Field var secondaryButtonTitle: String? = null
  @Field var countdownTitle: String? = null
  @Field var stopIntentBehavior: String? = null
  @Field var secondaryButtonBehavior: String? = null
  @Field var soundUri: String? = null
  @Field var soundName: String? = null
}

class AndroidAlarmOptionsRecord : Record {
  @Field var metadata: Map<String, Any>? = null
  @Field var alertTitle: String? = null
  @Field var alertBody: String? = null
  @Field var alertActionMode: String? = null
  @Field var stopButtonTitle: String? = null
  @Field var secondaryButtonTitle: String? = null
  @Field var stopIntentBehavior: String? = null
  @Field var secondaryButtonBehavior: String? = null
  @Field var soundName: String? = null
  @Field var soundUri: String? = null
  @Field var vibrate: Boolean? = null
  @Field var enforceVolume: Boolean? = null
  @Field var restoreVolume: Boolean? = null
  @Field var volume: Double? = null
  @Field var fullScreen: Boolean? = null
  @Field var fullScreenTarget: String? = null
  @Field var launchUri: String? = null
  @Field var maxRingDurationSeconds: Double? = null
  @Field var backupDelaySeconds: Double? = null
}

class AlarmSchedulerModule : Module() {
  private val observedEvents = mutableSetOf<String>()

  private val busListener = object : AlarmSchedulerEventBus.Listener {
    override fun onAlarmTriggered(alarm: Map<String, Any>) = emit("onAlarmTriggered", alarm)
    override fun onAlarmAction(action: Map<String, Any>) = emit("onAlarmAction", action)
    override fun onAlarmStateChange(event: Map<String, Any>) = emit("onAlarmStateChange", event)
  }

  override fun definition() = ModuleDefinition {
    Name("AlarmScheduler")

    Events("onAlarmTriggered", "onAlarmAction", "onAlarmStateChange")

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

    AsyncFunction("openFullScreenIntentSettingsAsync") {
      openFullScreenIntentSettings()
    }

    AsyncFunction("scheduleAlarmAsync") { alarm: AlarmScheduleRecord ->
      AlarmSchedulerScheduler.schedule(requireContext(), alarm)
    }

    AsyncFunction("cancelAlarmAsync") { id: String ->
      AlarmSchedulerScheduler.cancel(requireContext(), id)
    }

    AsyncFunction("getScheduledAlarmsAsync") {
      AlarmSchedulerScheduler.getAll(requireContext())
    }

    AsyncFunction("getCurrentAlarmContextAsync") {
      currentAlarmContext()
    }

    AsyncFunction("getPendingAlarmActionsAsync") {
      AlarmSchedulerStore.actions(requireContext()).map(AlarmSchedulerJson::toMap)
    }

    AsyncFunction("clearPendingAlarmActionsAsync") { ids: List<String>? ->
      AlarmSchedulerStore.clearActions(requireContext(), ids)
    }

    AsyncFunction("getPendingNativeAlarmHandoffAsync") {
      AlarmSchedulerStore.pendingHandoff(requireContext())?.let(AlarmSchedulerJson::toMap)
    }

    AsyncFunction("clearPendingNativeAlarmHandoffAsync") {
      AlarmSchedulerStore.clearPendingHandoff(requireContext())
    }

    AsyncFunction("completeNativeAlarmAsync") { alarmId: String ->
      val context = requireContext()
      // Order matters: mark complete first so a backup broadcast already in flight stays quiet.
      AlarmSchedulerStore.complete(context, alarmId)
      AlarmSchedulerScheduler.cancelBackups(context, alarmId)
      AlarmSchedulerRingService.complete(context, alarmId)
      AlarmSchedulerStore.clearActionsForAlarm(context, alarmId)
      AlarmSchedulerOccurrenceStore.all(context, alarmId).forEach { occurrence ->
        val phase = if (occurrence.optString("phase") == "ringing") "completed" else "cancelled"
        AlarmSchedulerOccurrenceStore.updatePhase(context, occurrence.optString("occurrenceId"), phase)
      }
      // A completed one-shot alarm has nothing left to schedule, so drop it from the native store
      // rather than leaving it in getScheduledAlarmsAsync() forever. Repeating alarms stay: they
      // already hold the next occurrence.
      val stored = AlarmSchedulerStore.alarm(context, alarmId)
      if (stored != null && AlarmSchedulerJson.intList(stored.optJSONArray("weekdays")).isEmpty()) {
        AlarmSchedulerStore.removeAlarm(context, alarmId)
        AlarmSchedulerSoundStore.delete(context, alarmId)
      }
    }

    AsyncFunction("resolveAlarmOccurrenceAsync") { occurrenceId: String, resolution: AlarmOccurrenceResolutionRecord ->
      AlarmSchedulerOccurrenceManager.resolve(requireContext(), occurrenceId, resolution)
    }

    AsyncFunction("getAlarmOccurrencesAsync") { alarmId: String? ->
      AlarmSchedulerOccurrenceStore.all(requireContext(), alarmId).map(AlarmSchedulerJson::toMap)
    }

    AsyncFunction("cancelAlarmOccurrenceAsync") { occurrenceId: String ->
      AlarmSchedulerOccurrenceManager.cancel(requireContext(), occurrenceId)
    }

    AsyncFunction("scheduleNativeAlarmBackupAsync") { alarmId: String, delaySeconds: Double? ->
      AlarmSchedulerScheduler.scheduleBackup(requireContext(), alarmId, delaySeconds)
    }

    AsyncFunction("cancelNativeAlarmBackupAsync") { alarmId: String ->
      AlarmSchedulerScheduler.cancelBackups(requireContext(), alarmId)
    }

    AsyncFunction("clearBypassAsync") { alarmId: String ->
      AlarmSchedulerStore.resetCompletion(requireContext(), alarmId)
    }

    AsyncFunction("resetNativeAlarmCompletionAsync") { alarmId: String ->
      AlarmSchedulerStore.resetCompletion(requireContext(), alarmId)
    }

    AsyncFunction("getNativeAlarmDebugStateAsync") { alarmId: String ->
      debugState(alarmId)
    }

    AsyncFunction("setSystemAlarmAsync") { alarm: AlarmScheduleRecord ->
      val context = requireContext()
      val hour = AlarmSchedulerScheduler.requireHour(alarm.hour)
      val minute = AlarmSchedulerScheduler.requireMinute(alarm.minute)
      val title = alarm.title?.takeIf { it.isNotBlank() } ?: "Alarm"
      val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
        putExtra(AlarmClock.EXTRA_HOUR, hour)
        putExtra(AlarmClock.EXTRA_MINUTES, minute)
        putExtra(AlarmClock.EXTRA_MESSAGE, title)
        putExtra(AlarmClock.EXTRA_SKIP_UI, !alarm.showUi)
        alarm.weekdays?.takeIf { it.isNotEmpty() }?.let { weekdays ->
          putIntegerArrayListExtra(AlarmClock.EXTRA_DAYS, ArrayList(weekdays.map(AlarmSchedulerScheduler::toCalendarDay)))
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

    OnStartObserving("onAlarmTriggered") { startObserving("onAlarmTriggered") }
    OnStopObserving("onAlarmTriggered") { stopObserving("onAlarmTriggered") }
    OnStartObserving("onAlarmAction") { startObserving("onAlarmAction") }
    OnStopObserving("onAlarmAction") { stopObserving("onAlarmAction") }
    OnStartObserving("onAlarmStateChange") { startObserving("onAlarmStateChange") }
    OnStopObserving("onAlarmStateChange") { stopObserving("onAlarmStateChange") }

    OnDestroy {
      observedEvents.clear()
      AlarmSchedulerEventBus.setListener(null)
    }
  }

  // region events

  private fun startObserving(event: String) {
    observedEvents.add(event)
    AlarmSchedulerEventBus.setListener(busListener)
  }

  private fun stopObserving(event: String) {
    observedEvents.remove(event)
    if (observedEvents.isEmpty()) {
      AlarmSchedulerEventBus.setListener(null)
    }
  }

  private fun emit(event: String, payload: Map<String, Any>) {
    if (!observedEvents.contains(event)) {
      return
    }
    runCatching { sendEvent(event, payload) }
  }

  // endregion

  private fun openFullScreenIntentSettings(): Boolean {
    val context = requireContext()
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      return false
    }
    val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
      data = Uri.parse("package:${context.packageName}")
      addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    if (intent.resolveActivity(context.packageManager) == null) {
      return false
    }
    context.startActivity(intent)
    return true
  }

  private fun currentAlarmContext(): Map<String, Any>? {
    val context = requireContext()
    val ringingId = AlarmSchedulerRingService.activeAlarmId() ?: AlarmSchedulerStore.activeRingAlarmId(context)
    if (ringingId != null) {
      AlarmSchedulerStore.alarm(context, ringingId)?.let { stored ->
        return alarmContext(stored, "alerting")
      }
    }
    AlarmSchedulerOccurrenceStore.all(context)
      .firstOrNull {
        it.optString("relationship") != "primary" &&
          it.optString("phase") == "scheduled" &&
          it.optLong("scheduledFor") > System.currentTimeMillis()
      }
      ?.let { occurrence ->
        val alarmId = occurrence.optString("alarmId")
        AlarmSchedulerStore.alarm(context, alarmId)?.let { stored ->
          val result = alarmContext(stored, "countdown").toMutableMap()
          result["occurrenceId"] = occurrence.optString("occurrenceId")
          result["nativeAlarmId"] = occurrence.optString("occurrenceId")
          result["relationship"] = occurrence.optString("relationship")
          occurrence.optJSONObject("metadata")?.let {
            result["metadata"] = AlarmSchedulerJson.toMap(it)
          }
          return result
        }
      }
    return recentFiredAlarmContext(context)
  }

  /**
   * Mirrors the iOS fallback: a one-shot alarm that fired within the last hour and was never
   * completed is still the alarm the app should be showing, even if the ring already timed out.
   */
  private fun recentFiredAlarmContext(context: Context): Map<String, Any>? {
    val now = System.currentTimeMillis()
    val windowMillis = 60 * 60 * 1000L
    return AlarmSchedulerStore.alarms(context)
      .filter { stored ->
        val timestamp = stored.optLong("timestamp")
        AlarmSchedulerJson.intList(stored.optJSONArray("weekdays")).isEmpty() &&
          timestamp in (now - windowMillis)..now &&
          !AlarmSchedulerStore.isComplete(context, stored.optString("id"))
      }
      .maxByOrNull { it.optLong("timestamp") }
      ?.let { alarmContext(it, "alerting") }
  }

  private fun alarmContext(stored: JSONObject, state: String): Map<String, Any> {
    val alarmId = stored.optString("id")
    val result = mutableMapOf<String, Any>(
      "id" to alarmId,
      "state" to state
    )
    stored.optJSONObject("metadata")?.let { result["metadata"] = AlarmSchedulerJson.toMap(it) }
    AlarmSchedulerOccurrenceStore.all(requireContext(), alarmId)
      .firstOrNull { it.optString("phase") == "ringing" }
      ?.let { occurrence ->
        result["occurrenceId"] = occurrence.optString("occurrenceId")
        result["nativeAlarmId"] = occurrence.optString("occurrenceId")
        result["relationship"] = occurrence.optString("relationship", "primary")
        occurrence.optJSONObject("metadata")?.let { result["metadata"] = AlarmSchedulerJson.toMap(it) }
      }
    return result
  }

  private fun debugState(alarmId: String): Map<String, Any?> {
    val context = requireContext()
    val stored = AlarmSchedulerStore.alarm(context, alarmId)
    val options = AlarmSchedulerOptions.fromJson(
      stored?.optJSONObject("options"),
      stored?.optString("title") ?: "Alarm",
      alarmId
    )
    return mapOf(
      "alarmId" to alarmId,
      "isComplete" to AlarmSchedulerStore.isComplete(context, alarmId),
      "activeRetryAlarmIds" to AlarmSchedulerStore.retryAlarmIds(context, alarmId),
      "pendingActions" to AlarmSchedulerStore.actions(context)
        .filter { it.optString("alarmId") == alarmId }
        .map(AlarmSchedulerJson::toMap),
      "pendingHandoff" to AlarmSchedulerStore.pendingHandoff(context)?.let(AlarmSchedulerJson::toMap),
      "intentDebugCounts" to AlarmSchedulerStore.intentDebugCounts(context, alarmId),
      "currentContext" to currentAlarmContext(),
      "alertActionMode" to options.alertActionMode,
      "stopButtonIncluded" to (options.alertActionMode != ALERT_ACTION_MODE_OPEN_APP_ONLY),
      "secondaryButtonIncluded" to true,
      "secondaryButtonBehavior" to options.secondaryButtonBehavior,
      "stopIntentBehavior" to options.stopIntentBehavior,
      "alertInitializer" to "androidRingService",
      "runtimeSupportsSecondaryOnlyAlert" to true,
      "sound" to if (options.soundName == null && options.soundUri == null) "default" else "named",
      "soundName" to options.soundName,
      "soundUri" to options.soundUri,
      "isRinging" to (AlarmSchedulerRingService.activeAlarmId() == alarmId),
      "isScheduled" to (stored != null),
      "canUseFullScreenIntent" to canUseFullScreenIntent(),
      "canScheduleExactAlarms" to canScheduleExactAlarms()
    )
  }

  private fun requireContext() = appContext.reactContext
    ?: throw IllegalStateException("React context is not available.")

  private fun canScheduleExactAlarms(): Boolean {
    val alarmManager = requireContext().getSystemService(AlarmManager::class.java)
    return Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()
  }

  private fun canUseFullScreenIntent(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      return true
    }
    val notificationManager = requireContext().getSystemService(NotificationManager::class.java)
    return notificationManager?.canUseFullScreenIntent() ?: false
  }

  private fun permissions(): Map<String, Any> {
    val canSchedule = canScheduleExactAlarms()
    return mapOf(
      "platform" to "android",
      "status" to if (canSchedule) "authorized" else "denied",
      "canScheduleExactAlarms" to canSchedule,
      "canOpenSettings" to (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S),
      "canUseFullScreenIntent" to canUseFullScreenIntent(),
      "canPostNotifications" to AlarmSchedulerRingService.canPostNotifications(requireContext())
    )
  }
}
