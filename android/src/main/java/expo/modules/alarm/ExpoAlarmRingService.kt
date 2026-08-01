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
class ExpoAlarmRingService : Service() {
  private var mediaPlayer: MediaPlayer? = null
  private var vibrator: Vibrator? = null
  private var wakeLock: PowerManager.WakeLock? = null
  private var volumeObserver: ContentObserver? = null
  private var previousAlarmVolume: Int? = null
  private var targetAlarmVolume: Int? = null
  private var timeoutRunnable: Runnable? = null
  private val handler = Handler(Looper.getMainLooper())

  private var alarmId: String? = null
  private var options: ExpoAlarmOptions? = null

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
    val stored = id?.let { ExpoAlarmStore.alarm(this, it) }
    if (id == null || stored == null) {
      stopRinging()
      return
    }

    val resolved = ExpoAlarmOptions.fromJson(
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
    ExpoAlarmStore.setActiveRingAlarmId(this, id)

    startForegroundNotification(id, resolved)
    acquireWakeLock(resolved)
    enforceAlarmVolume(resolved)
    startPlayback(resolved)
    startVibration(resolved)
    scheduleTimeout(id, resolved)
    presentFullScreen(id, resolved, intent.getBooleanExtra(EXTRA_IS_BACKUP, false))

    // Persisted first, then emitted: a cold-launched app replays this through
    // getPendingNativeAlarmHandoffAsync(), a warm app gets the live event.
    ExpoAlarmStore.recordHandoff(
      context = this,
      alarmId = id,
      action = "secondaryOpen",
      details = mapOf(
        "foregroundRequested" to true,
        "trigger" to true
      )
    )
    ExpoAlarmEventBus.emitTriggered(ExpoAlarmScheduler.serialize(stored))
    ExpoAlarmEventBus.emitStateChange(id, "alerting", stored.optJSONObject("metadata"))
  }

  private fun resumeOrStop() {
    val resumeId = ExpoAlarmStore.activeRingAlarmId(this)
    if (resumeId == null || ExpoAlarmStore.isComplete(this, resumeId)) {
      stopRinging()
      return
    }
    handleStart(
      Intent(this, ExpoAlarmRingService::class.java).apply {
        action = ACTION_START
        putExtra(EXTRA_ALARM_ID, resumeId)
      }
    )
  }

  /** The app finished its mission — this is the only silent, no-re-arm exit. */
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
    val resolved = options ?: ExpoAlarmOptions.fromJson(
      ExpoAlarmStore.alarm(this, currentId)?.optJSONObject("options"),
      ExpoAlarmStore.alarm(this, currentId)?.optString("title") ?: "Alarm",
      currentId
    )
    val details = mutableMapOf<String, Any?>("foregroundRequested" to true)

    val shouldReschedule = resolved.stopIntentBehavior == STOP_BEHAVIOR_RESCHEDULE &&
      !ExpoAlarmStore.isComplete(this, currentId)
    if (shouldReschedule) {
      val backup = ExpoAlarmScheduler.scheduleBackup(this, currentId, resolved.backupDelaySeconds)
      details["rescheduled"] = backup["scheduled"]
      details["rescheduledAlarmId"] = backup["backupAlarmId"]
      details["backupAlarmId"] = backup["backupAlarmId"]
      details["backupDelaySeconds"] = backup["delaySeconds"]
      backup["scheduledFor"]?.let {
        details["retryScheduledFor"] = it
        details["backupScheduledFor"] = it
      }
    }

    ExpoAlarmStore.recordHandoff(this, currentId, "nativeStop", details = details)
    if (resolved.stopIntentBehavior == STOP_BEHAVIOR_OPEN_APP) {
      openApp(currentId, resolved)
    }
    stopRinging()
  }

  /** The user chose "open the app" — keep ringing until the app says the mission is done. */
  private fun handleOpen(id: String?) {
    val currentId = id ?: alarmId ?: return
    val resolved = options ?: return
    ExpoAlarmStore.recordHandoff(
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
    ExpoAlarmStore.setActiveRingAlarmId(this, null)
    if (id != null) {
      ExpoAlarmEventBus.emitStateChange(id, "scheduled", ExpoAlarmStore.alarm(this, id)?.optJSONObject("metadata"))
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

  private fun startPlayback(options: ExpoAlarmOptions) {
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

  private fun candidateSoundUris(options: ExpoAlarmOptions): List<Uri> {
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
  private fun enforceAlarmVolume(options: ExpoAlarmOptions) {
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

  private fun startVibration(options: ExpoAlarmOptions) {
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

  private fun acquireWakeLock(options: ExpoAlarmOptions) {
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

  private fun scheduleTimeout(id: String, options: ExpoAlarmOptions) {
    if (options.maxRingDurationSeconds <= 0) {
      return
    }
    val runnable = Runnable {
      if (alarmId != id) {
        return@Runnable
      }
      // Time-boxing the ring protects the battery, but an unfinished mission must still come
      // back when the app asked for rescheduleImmediate.
      if (options.stopIntentBehavior == STOP_BEHAVIOR_RESCHEDULE && !ExpoAlarmStore.isComplete(this, id)) {
        ExpoAlarmScheduler.scheduleBackup(this, id, TIMEOUT_BACKUP_DELAY_SECONDS)
      }
      ExpoAlarmStore.record(this, id, "dismiss", details = mapOf("timedOut" to true))
      stopRinging()
    }
    timeoutRunnable = runnable
    handler.postDelayed(runnable, (options.maxRingDurationSeconds * 1000).roundToLong())
  }

  // endregion

  // region presentation

  private fun startForegroundNotification(id: String, options: ExpoAlarmOptions) {
    createChannel()
    val notification = buildNotification(id, options)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
      startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }
  }

  private fun createChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }
    val manager = getSystemService(NotificationManager::class.java) ?: return
    // Sound is owned by the service's MediaPlayer, so the channel itself stays silent to avoid
    // a second, unstoppable audio stream.
    val channel = NotificationChannel(CHANNEL_ID, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
      setSound(null, null)
      enableVibration(false)
      setBypassDnd(true)
      lockscreenVisibility = Notification.VISIBILITY_PUBLIC
      setShowBadge(false)
    }
    manager.createNotificationChannel(channel)
  }

  private fun buildNotification(id: String, options: ExpoAlarmOptions): Notification {
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(this, CHANNEL_ID)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
    }

    val contentIntent = fullScreenPendingIntent(id, options)
    builder
      .setSmallIcon(applicationInfo.icon)
      .setContentTitle(options.alertTitle)
      .setContentText(options.alertBody)
      .setCategory(Notification.CATEGORY_ALARM)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .setOngoing(true)
      .setAutoCancel(false)
      .setContentIntent(contentIntent)

    if (options.fullScreen) {
      builder.setFullScreenIntent(contentIntent, true)
    }

    builder.addAction(
      buildAction(
        options.secondaryButtonTitle,
        servicePendingIntent(ACTION_OPEN, id, "open")
      )
    )
    if (options.alertActionMode != ALERT_ACTION_MODE_OPEN_MISSION_ONLY) {
      builder.addAction(
        buildAction(
          options.stopButtonTitle,
          servicePendingIntent(ACTION_STOP, id, "stop")
        )
      )
    }

    return builder.build()
  }

  private fun buildAction(title: String, intent: PendingIntent): Notification.Action {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      Notification.Action.Builder(null as android.graphics.drawable.Icon?, title, intent).build()
    } else {
      @Suppress("DEPRECATION")
      Notification.Action.Builder(0, title, intent).build()
    }
  }

  private fun servicePendingIntent(action: String, id: String, suffix: String): PendingIntent {
    val intent = Intent(this, ExpoAlarmRingService::class.java).apply {
      this.action = action
      putExtra(EXTRA_ALARM_ID, id)
    }
    return PendingIntent.getService(
      this,
      ExpoAlarmScheduler.requestCode("$suffix-$id"),
      intent,
      ExpoAlarmScheduler.pendingFlags()
    )
  }

  private fun fullScreenPendingIntent(id: String, options: ExpoAlarmOptions): PendingIntent {
    if (options.fullScreenTarget == FULL_SCREEN_TARGET_APP) {
      return PendingIntent.getActivity(
        this,
        ExpoAlarmScheduler.requestCode("app-$id"),
        appIntent(id, options) ?: Intent(),
        ExpoAlarmScheduler.pendingFlags()
      )
    }
    return PendingIntent.getActivity(
      this,
      ExpoAlarmScheduler.requestCode("ring-$id"),
      ExpoAlarmRingActivity.intent(this, id),
      ExpoAlarmScheduler.pendingFlags()
    )
  }

  /**
   * setAlarmClock grants a background activity-start allowance, so launching directly is both
   * legal and far more reliable than relying on the full-screen intent alone.
   */
  private fun presentFullScreen(id: String, options: ExpoAlarmOptions, isBackup: Boolean) {
    if (!options.fullScreen) {
      return
    }
    val intent = if (options.fullScreenTarget == FULL_SCREEN_TARGET_APP) {
      appIntent(id, options)
    } else {
      ExpoAlarmRingActivity.intent(this, id).putExtra(EXTRA_IS_BACKUP, isBackup)
    }
    if (intent == null) {
      return
    }
    runCatching { startActivity(intent) }
  }

  private fun openApp(id: String, options: ExpoAlarmOptions) {
    val intent = appIntent(id, options) ?: return
    runCatching { startActivity(intent) }
  }

  private fun appIntent(id: String, options: ExpoAlarmOptions): Intent? {
    val intent = ExpoAlarmScheduler.launchIntent(this) ?: return null
    options.launchUri?.let { template ->
      val uri = if (template.contains(ALARM_ID_PLACEHOLDER)) {
        template.replace(ALARM_ID_PLACEHOLDER, Uri.encode(id))
      } else {
        val separator = if (template.contains("?")) "&" else "?"
        "$template${separator}alarmId=${Uri.encode(id)}"
      }
      intent.data = runCatching { Uri.parse(uri) }.getOrNull()
    }
    return intent
      .putExtra(EXTRA_ALARM_ID, id)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
  }

  // endregion

  companion object {
    const val ACTION_START = "expo.modules.alarm.RING_START"
    const val ACTION_STOP = "expo.modules.alarm.RING_STOP"
    const val ACTION_OPEN = "expo.modules.alarm.RING_OPEN"
    const val ACTION_COMPLETE = "expo.modules.alarm.RING_COMPLETE"
    const val EXTRA_ALARM_ID = "expo.modules.alarm.extra.ALARM_ID"
    const val EXTRA_IS_BACKUP = "expo.modules.alarm.extra.RING_IS_BACKUP"

    private const val CHANNEL_ID = "expo_alarm_ring"
    private const val NOTIFICATION_ID = 0xA1A2
    private const val WAKE_LOCK_TAG = "ExpoAlarm:ring"
    private const val DEFAULT_WAKE_LOCK_TIMEOUT_MILLIS = 10 * 60 * 1000L
    private const val TIMEOUT_BACKUP_DELAY_SECONDS = 60.0
    private const val ALARM_ID_PLACEHOLDER = "{alarmId}"

    @Volatile
    private var activeAlarmId: String? = null

    fun activeAlarmId(): String? = activeAlarmId

    fun start(context: Context, alarmId: String, isBackup: Boolean) {
      val intent = Intent(context, ExpoAlarmRingService::class.java).apply {
        action = ACTION_START
        putExtra(EXTRA_ALARM_ID, alarmId)
        putExtra(EXTRA_IS_BACKUP, isBackup)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
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
      val intent = Intent(context, ExpoAlarmRingService::class.java).apply {
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
