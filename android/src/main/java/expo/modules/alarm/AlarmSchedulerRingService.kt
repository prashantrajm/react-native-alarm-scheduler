package expo.modules.alarm

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.database.ContentObserver
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/**
 * Owns a ringing alarm for as long as it takes the user to finish whatever the app demands of
 * them. Nothing but [ACTION_COMPLETE] (driven by `completeNativeAlarmAsync`), an explicit stop, or
 * the configured timeout can silence it — swiping notifications and pressing volume keys cannot.
 */
class AlarmSchedulerRingService : Service() {
  private var mediaPlayer: MediaPlayer? = null
  private var vibrator: Vibrator? = null
  private var wakeLock: PowerManager.WakeLock? = null
  private var volumeObserver: ContentObserver? = null
  private var previousAlarmVolume: Int? = null
  private var targetAlarmVolume: Int? = null
  private var timeoutRunnable: Runnable? = null
  private val handler = Handler(Looper.getMainLooper())

  private var alarmId: String? = null
  private var options: AlarmSchedulerOptions? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_START -> handleStart(intent)
      ACTION_COMPLETE -> handleComplete(intent.getStringExtra(EXTRA_ALARM_ID))
      ACTION_STOP -> handleUserStop(intent.getStringExtra(EXTRA_ALARM_ID))
      ACTION_OPEN -> handleOpen(intent.getStringExtra(EXTRA_ALARM_ID))
      // A null intent means the system restarted a sticky service after killing the process
      // mid-ring. Pick the alarm back up rather than leaving the user un-woken.
      null -> resumeOrStop()
      else -> stopRinging()
    }
    return START_STICKY
  }

  override fun onDestroy() {
    stopPlayback()
    super.onDestroy()
  }

  // region lifecycle

  private fun handleStart(intent: Intent) {
    val id = intent.getStringExtra(EXTRA_ALARM_ID)
    val stored = id?.let { AlarmSchedulerStore.alarm(this, it) }
    if (id == null || stored == null) {
      stopRinging()
      return
    }

    val resolved = AlarmSchedulerOptions.fromJson(
      stored.optJSONObject("options"),
      stored.optString("title", "Alarm"),
      id
    )

    // A second broadcast for an alarm that is already ringing (a backup catching up, say) must
    // not restart playback or stack notifications.
    if (alarmId == id && mediaPlayer != null) {
      startForegroundNotification(id, resolved)
      return
    }

    alarmId = id
    options = resolved
    activeAlarmId = id
    AlarmSchedulerStore.setActiveRingAlarmId(this, id)

    startForegroundNotification(id, resolved)
    acquireWakeLock(resolved)
    enforceAlarmVolume(resolved)
    startPlayback(resolved)
    startVibration(resolved)
    scheduleTimeout(id, resolved)
    presentFullScreen(id, resolved, intent.getBooleanExtra(EXTRA_IS_BACKUP, false))

    // The handoff record and onAlarmTriggered are emitted by the receiver before this service is
    // even asked to start, so they survive the service being refused.
    AlarmSchedulerEventBus.emitStateChange(id, "alerting", stored.optJSONObject("metadata"))
  }

  private fun resumeOrStop() {
    val resumeId = AlarmSchedulerStore.activeRingAlarmId(this)
    if (resumeId == null || AlarmSchedulerStore.isComplete(this, resumeId)) {
      stopRinging()
      return
    }
    handleStart(
      Intent(this, AlarmSchedulerRingService::class.java).apply {
        action = ACTION_START
        putExtra(EXTRA_ALARM_ID, resumeId)
      }
    )
  }

  /** The app reported completion — this is the only silent, no-re-arm exit. */
  private fun handleComplete(id: String?) {
    // A mismatch only matters while some *other* alarm is actually ringing; otherwise this is a
    // completion arriving at an idle service, which must still shut itself down.
    if (id != null && alarmId != null && id != alarmId) {
      return
    }
    stopRinging()
  }

  /** An explicit stop from the notification action or the ring screen's stop button. */
  private fun handleUserStop(id: String?) {
    val currentId = id ?: alarmId ?: return stopRinging()
    val resolved = options ?: AlarmSchedulerOptions.fromJson(
      AlarmSchedulerStore.alarm(this, currentId)?.optJSONObject("options"),
      AlarmSchedulerStore.alarm(this, currentId)?.optString("title") ?: "Alarm",
      currentId
    )
    val details = mutableMapOf<String, Any?>("foregroundRequested" to true)

    val shouldReschedule = resolved.stopIntentBehavior == STOP_BEHAVIOR_RESCHEDULE &&
      !AlarmSchedulerStore.isComplete(this, currentId)
    if (shouldReschedule) {
      val backup = AlarmSchedulerScheduler.scheduleBackup(this, currentId, resolved.backupDelaySeconds)
      details["rescheduled"] = backup["scheduled"]
      details["rescheduledAlarmId"] = backup["backupAlarmId"]
      details["backupAlarmId"] = backup["backupAlarmId"]
      details["backupDelaySeconds"] = backup["delaySeconds"]
      backup["scheduledFor"]?.let {
        details["retryScheduledFor"] = it
        details["backupScheduledFor"] = it
      }
    }

    AlarmSchedulerStore.recordHandoff(this, currentId, "nativeStop", details = details)
    if (resolved.stopIntentBehavior == STOP_BEHAVIOR_OPEN_APP) {
      openApp(currentId, resolved)
    }
    stopRinging()
  }

  /** The user chose "open the app" — keep ringing until the app reports completion. */
  private fun handleOpen(id: String?) {
    val currentId = id ?: alarmId ?: return
    val resolved = options ?: return
    AlarmSchedulerStore.recordHandoff(
      context = this,
      alarmId = currentId,
      action = "secondaryOpen",
      details = mapOf("foregroundRequested" to true)
    )
    openApp(currentId, resolved)
  }

  private fun stopRinging() {
    val id = alarmId
    stopPlayback()
    activeAlarmId = null
    AlarmSchedulerStore.setActiveRingAlarmId(this, null)
    if (id != null) {
      AlarmSchedulerEventBus.emitStateChange(id, "scheduled", AlarmSchedulerStore.alarm(this, id)?.optJSONObject("metadata"))
    }
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  private fun stopPlayback() {
    timeoutRunnable?.let(handler::removeCallbacks)
    timeoutRunnable = null

    runCatching {
      mediaPlayer?.stop()
      mediaPlayer?.release()
    }
    mediaPlayer = null

    runCatching { vibrator?.cancel() }
    vibrator = null

    volumeObserver?.let { runCatching { contentResolver.unregisterContentObserver(it) } }
    volumeObserver = null
    restoreAlarmVolume()

    runCatching {
      if (wakeLock?.isHeld == true) {
        wakeLock?.release()
      }
    }
    wakeLock = null
    alarmId = null
    options = null
  }

  // endregion

  // region audio

  private fun startPlayback(options: AlarmSchedulerOptions) {
    val attributes = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_ALARM)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()

    for (uri in candidateSoundUris(options)) {
      val player = MediaPlayer()
      val started = runCatching {
        player.setAudioAttributes(attributes)
        player.setDataSource(this, uri)
        player.isLooping = true
        player.prepare()
        player.start()
      }.isSuccess
      if (started) {
        mediaPlayer = player
        return
      }
      runCatching { player.release() }
    }
  }

  private fun candidateSoundUris(options: AlarmSchedulerOptions): List<Uri> {
    val candidates = mutableListOf<Uri>()
    options.soundUri?.let { runCatching { Uri.parse(it) }.getOrNull()?.let(candidates::add) }
    options.soundName?.let { name ->
      val bare = name.substringBeforeLast('.')
      val resourceId = resources.getIdentifier(bare, "raw", packageName)
      if (resourceId != 0) {
        candidates.add(Uri.parse("android.resource://$packageName/$resourceId"))
      }
    }
    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)?.let(candidates::add)
    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)?.let(candidates::add)
    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)?.let(candidates::add)
    return candidates
  }

  /**
   * The Android half of the audibility story: the alarm stream is pinned to the configured level
   * and re-pinned whenever anything (a volume key, another app) lowers it.
   */
  private fun enforceAlarmVolume(options: AlarmSchedulerOptions) {
    if (!options.enforceVolume) {
      return
    }
    val audioManager = getSystemService(AudioManager::class.java) ?: return
    val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
    val target = (maxVolume * options.volume).roundToInt().coerceIn(1, maxVolume)
    previousAlarmVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
    targetAlarmVolume = target
    runCatching { audioManager.setStreamVolume(AudioManager.STREAM_ALARM, target, 0) }

    val observer = object : ContentObserver(handler) {
      override fun onChange(selfChange: Boolean) {
        val desired = targetAlarmVolume ?: return
        if (audioManager.getStreamVolume(AudioManager.STREAM_ALARM) < desired) {
          runCatching { audioManager.setStreamVolume(AudioManager.STREAM_ALARM, desired, 0) }
        }
      }
    }
    runCatching {
      contentResolver.registerContentObserver(Settings.System.CONTENT_URI, true, observer)
      volumeObserver = observer
    }
  }

  private fun restoreAlarmVolume() {
    val previous = previousAlarmVolume ?: return
    previousAlarmVolume = null
    targetAlarmVolume = null
    if (options?.restoreVolume == false) {
      return
    }
    val audioManager = getSystemService(AudioManager::class.java) ?: return
    runCatching { audioManager.setStreamVolume(AudioManager.STREAM_ALARM, previous, 0) }
  }

  private fun startVibration(options: AlarmSchedulerOptions) {
    if (!options.vibrate) {
      return
    }
    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
      @Suppress("DEPRECATION")
      getSystemService(Vibrator::class.java)
    } ?: return

    val pattern = longArrayOf(0, 800, 700)
    val attributes = AudioAttributes.Builder()
      .setUsage(AudioAttributes.USAGE_ALARM)
      .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
      .build()
    runCatching {
      when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> device.vibrate(
          VibrationEffect.createWaveform(pattern, 0),
          VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM)
        )

        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> @Suppress("DEPRECATION")
        device.vibrate(VibrationEffect.createWaveform(pattern, 0), attributes)

        else -> @Suppress("DEPRECATION")
        device.vibrate(pattern, 0, attributes)
      }
      vibrator = device
    }
  }

  private fun acquireWakeLock(options: AlarmSchedulerOptions) {
    val powerManager = getSystemService(PowerManager::class.java) ?: return
    val timeout = if (options.maxRingDurationSeconds > 0) {
      (options.maxRingDurationSeconds * 1000).roundToLong()
    } else {
      DEFAULT_WAKE_LOCK_TIMEOUT_MILLIS
    }
    runCatching {
      val lock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
      lock.setReferenceCounted(false)
      lock.acquire(timeout)
      wakeLock = lock
    }
  }

  private fun scheduleTimeout(id: String, options: AlarmSchedulerOptions) {
    if (options.maxRingDurationSeconds <= 0) {
      return
    }
    val runnable = Runnable {
      if (alarmId != id) {
        return@Runnable
      }
      // Time-boxing the ring protects the battery, but an alarm the app never completed must
      // still come back when it asked for rescheduleImmediate.
      if (options.stopIntentBehavior == STOP_BEHAVIOR_RESCHEDULE && !AlarmSchedulerStore.isComplete(this, id)) {
        AlarmSchedulerScheduler.scheduleBackup(this, id, TIMEOUT_BACKUP_DELAY_SECONDS)
      }
      AlarmSchedulerStore.record(this, id, "dismiss", details = mapOf("timedOut" to true))
      stopRinging()
    }
    timeoutRunnable = runnable
    handler.postDelayed(runnable, (options.maxRingDurationSeconds * 1000).roundToLong())
  }

  // endregion

  // region presentation

  private fun startForegroundNotification(id: String, options: AlarmSchedulerOptions) {
    val notification = AlarmSchedulerNotifications.buildRingNotification(this, id, options)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      startForeground(
        AlarmSchedulerNotifications.RING_NOTIFICATION_ID,
        notification,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
      )
    } else {
      startForeground(AlarmSchedulerNotifications.RING_NOTIFICATION_ID, notification)
    }
  }

  /**
   * setAlarmClock grants a background activity-start allowance, so launching directly is both
   * legal and far more reliable than relying on the full-screen intent alone.
   */
  private fun presentFullScreen(id: String, options: AlarmSchedulerOptions, isBackup: Boolean) {
    if (!options.fullScreen) {
      return
    }
    val intent = if (options.fullScreenTarget == FULL_SCREEN_TARGET_APP) {
      AlarmSchedulerNotifications.appIntent(this, id, options)
    } else {
      AlarmSchedulerRingActivity.intent(this, id).putExtra(EXTRA_IS_BACKUP, isBackup)
    }
    if (intent == null) {
      return
    }
    runCatching { startActivity(intent) }
  }

  private fun openApp(id: String, options: AlarmSchedulerOptions) {
    val intent = AlarmSchedulerNotifications.appIntent(this, id, options) ?: return
    runCatching { startActivity(intent) }
  }

  // endregion

  companion object {
    const val ACTION_START = "expo.modules.alarm.RING_START"
    const val ACTION_STOP = "expo.modules.alarm.RING_STOP"
    const val ACTION_OPEN = "expo.modules.alarm.RING_OPEN"
    const val ACTION_COMPLETE = "expo.modules.alarm.RING_COMPLETE"
    const val EXTRA_ALARM_ID = "expo.modules.alarm.extra.ALARM_ID"
    const val EXTRA_IS_BACKUP = "expo.modules.alarm.extra.RING_IS_BACKUP"

    private const val WAKE_LOCK_TAG = "AlarmScheduler:ring"
    private const val DEFAULT_WAKE_LOCK_TIMEOUT_MILLIS = 10 * 60 * 1000L
    private const val TIMEOUT_BACKUP_DELAY_SECONDS = 60.0

    @Volatile
    private var activeAlarmId: String? = null

    fun activeAlarmId(): String? = activeAlarmId

    /**
     * Returns false when the platform refused to start the service — a revoked exact-alarm grant,
     * an OEM restriction, or any other background-start denial. Callers must fall back rather than
     * propagate: an exception here would otherwise kill the broadcast receiver and the alarm with
     * it, which is the one outcome an alarm library may never produce.
     */
    fun start(context: Context, alarmId: String, isBackup: Boolean): Boolean {
      val intent = Intent(context, AlarmSchedulerRingService::class.java).apply {
        action = ACTION_START
        putExtra(EXTRA_ALARM_ID, alarmId)
        putExtra(EXTRA_IS_BACKUP, isBackup)
      }
      return runCatching {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
          context.startForegroundService(intent)
        } else {
          context.startService(intent)
        }
      }.isSuccess
    }

    fun complete(context: Context, alarmId: String) {
      send(context, ACTION_COMPLETE, alarmId)
    }

    fun stopIfRinging(context: Context, alarmId: String) {
      if (activeAlarmId == alarmId) {
        send(context, ACTION_COMPLETE, alarmId)
      }
    }

    private fun send(context: Context, action: String, alarmId: String) {
      val intent = Intent(context, AlarmSchedulerRingService::class.java).apply {
        this.action = action
        putExtra(EXTRA_ALARM_ID, alarmId)
      }
      runCatching { context.startService(intent) }
    }

    fun canPostNotifications(context: Context): Boolean {
      if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
        return true
      }
      return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED
    }
  }
}
