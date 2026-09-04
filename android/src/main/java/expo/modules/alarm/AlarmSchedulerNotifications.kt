package expo.modules.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build

/**
 * Notification plumbing shared by the ringing service and the no-service fallback.
 *
 * Two channels exist on purpose. The service owns its own audio, so its channel is silent —
 * otherwise the alarm would play twice from two places, only one of which can be stopped. The
 * fallback has no service and therefore no MediaPlayer, so its channel carries the alarm sound.
 */
internal object AlarmSchedulerNotifications {
  const val RING_NOTIFICATION_ID = 0xA1A2
  const val FALLBACK_NOTIFICATION_ID = 0xA1A3

  private const val CHANNEL_RING = "alarm_scheduler_ring"
  private const val CHANNEL_FALLBACK = "alarm_scheduler_fallback"

  fun buildRingNotification(context: Context, alarmId: String, options: AlarmSchedulerOptions): Notification {
    createRingChannel(context)
    return build(context, alarmId, options, CHANNEL_RING, ongoing = true)
  }

  /**
   * Last resort when the foreground service cannot be started — an OEM restriction, a revoked
   * exact-alarm grant, or any other denial. Rings through the notification channel instead of the
   * service so the user is still woken, as loudly as the platform allows without a service.
   */
  fun postFallbackNotification(context: Context, alarmId: String, options: AlarmSchedulerOptions) {
    val channelId = createFallbackChannel(context, options)
    val notification = build(context, alarmId, options, channelId, ongoing = false)
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    runCatching { manager.notify(FALLBACK_NOTIFICATION_ID, notification) }
  }

  private fun build(
    context: Context,
    alarmId: String,
    options: AlarmSchedulerOptions,
    channelId: String,
    ongoing: Boolean
  ): Notification {
    val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      Notification.Builder(context, channelId)
    } else {
      @Suppress("DEPRECATION")
      Notification.Builder(context).setPriority(Notification.PRIORITY_MAX)
    }

    val contentIntent = fullScreenPendingIntent(context, alarmId, options)
    builder
      .setSmallIcon(context.applicationInfo.icon)
      .setContentTitle(options.alertTitle)
      .setContentText(options.alertBody)
      .setCategory(Notification.CATEGORY_ALARM)
      .setVisibility(Notification.VISIBILITY_PUBLIC)
      .setOngoing(ongoing)
      .setAutoCancel(false)
      .setContentIntent(contentIntent)

    if (options.fullScreen) {
      builder.setFullScreenIntent(contentIntent, true)
    }
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O && !ongoing) {
      @Suppress("DEPRECATION")
      builder.setSound(fallbackSoundUri(context, options))
    }

    builder.addAction(
      action(options.secondaryButtonTitle, servicePendingIntent(context, AlarmSchedulerRingService.ACTION_OPEN, alarmId, "open"))
    )
    if (options.alertActionMode != ALERT_ACTION_MODE_OPEN_APP_ONLY) {
      builder.addAction(
        action(options.stopButtonTitle, servicePendingIntent(context, AlarmSchedulerRingService.ACTION_STOP, alarmId, "stop"))
      )
    }

    return builder.build()
  }

  private fun action(title: String, intent: PendingIntent): Notification.Action {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      Notification.Action.Builder(null as Icon?, title, intent).build()
    } else {
      @Suppress("DEPRECATION")
      Notification.Action.Builder(0, title, intent).build()
    }
  }

  private fun createRingChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return
    }
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    manager.createNotificationChannel(
      NotificationChannel(CHANNEL_RING, "Alarms", NotificationManager.IMPORTANCE_HIGH).apply {
        setSound(null, null)
        enableVibration(false)
        setBypassDnd(true)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        setShowBadge(false)
      }
    )
  }

  private fun createFallbackChannel(context: Context, options: AlarmSchedulerOptions): String {
    val sound = fallbackSoundUri(context, options)
    val channelId = "${CHANNEL_FALLBACK}_${sound.toString().hashCode().toUInt().toString(16)}"
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
      return channelId
    }
    val manager = context.getSystemService(NotificationManager::class.java) ?: return channelId
    manager.createNotificationChannel(
      NotificationChannel(channelId, "Alarms (fallback)", NotificationManager.IMPORTANCE_HIGH).apply {
        setSound(
          sound,
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        )
        enableVibration(options.vibrate)
        setBypassDnd(true)
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        setShowBadge(false)
      }
    )
    return channelId
  }

  private fun fallbackSoundUri(context: Context, options: AlarmSchedulerOptions): Uri? {
    options.soundUri?.let { raw ->
      runCatching { Uri.parse(raw) }.getOrNull()?.takeUnless { it.scheme == "file" }?.let { return it }
    }
    options.soundName?.let { name ->
      val resourceId = context.resources.getIdentifier(name.substringBeforeLast('.'), "raw", context.packageName)
      if (resourceId != 0) {
        return Uri.parse("android.resource://${context.packageName}/$resourceId")
      }
    }
    return RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
  }

  fun servicePendingIntent(context: Context, action: String, alarmId: String, suffix: String): PendingIntent {
    val intent = Intent(context, AlarmSchedulerRingService::class.java).apply {
      this.action = action
      putExtra(AlarmSchedulerRingService.EXTRA_ALARM_ID, alarmId)
    }
    return PendingIntent.getService(
      context,
      AlarmSchedulerScheduler.requestCode("$suffix-$alarmId"),
      intent,
      AlarmSchedulerScheduler.pendingFlags()
    )
  }

  fun fullScreenPendingIntent(context: Context, alarmId: String, options: AlarmSchedulerOptions): PendingIntent {
    if (options.fullScreenTarget == FULL_SCREEN_TARGET_APP) {
      return PendingIntent.getActivity(
        context,
        AlarmSchedulerScheduler.requestCode("app-$alarmId"),
        appIntent(context, alarmId, options) ?: Intent(),
        AlarmSchedulerScheduler.pendingFlags()
      )
    }
    return PendingIntent.getActivity(
      context,
      AlarmSchedulerScheduler.requestCode("ring-$alarmId"),
      AlarmSchedulerRingActivity.intent(context, alarmId),
      AlarmSchedulerScheduler.pendingFlags()
    )
  }

  fun appIntent(context: Context, alarmId: String, options: AlarmSchedulerOptions): Intent? {
    val intent = AlarmSchedulerScheduler.launchIntent(context) ?: return null
    options.launchUri?.let { template ->
      val uri = if (template.contains(ALARM_ID_PLACEHOLDER)) {
        template.replace(ALARM_ID_PLACEHOLDER, Uri.encode(alarmId))
      } else {
        val separator = if (template.contains("?")) "&" else "?"
        "$template${separator}alarmId=${Uri.encode(alarmId)}"
      }
      intent.data = runCatching { Uri.parse(uri) }.getOrNull()
    }
    return intent
      .putExtra(AlarmSchedulerRingService.EXTRA_ALARM_ID, alarmId)
      .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
  }

  private const val ALARM_ID_PLACEHOLDER = "{alarmId}"
}
