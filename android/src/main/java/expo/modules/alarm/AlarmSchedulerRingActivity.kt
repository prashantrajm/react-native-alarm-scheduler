package expo.modules.alarm

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The lock-screen ringing surface.
 *
 * Android — unlike AlarmKit — lets the app own this screen outright, so there is no system Stop
 * button to work around: when `alertActionMode` is `openAppOnly` the only way out is the
 * button that hands off to the app. The UI is built in code so the library ships no resources and
 * inherits no theme from the host app.
 */
class AlarmSchedulerRingActivity : Activity() {
  private var alarmId: String? = null
  private var options: AlarmSchedulerOptions? = null

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    showOverLockScreen()
    bind(intent)
  }

  override fun onNewIntent(intent: Intent?) {
    super.onNewIntent(intent)
    if (intent != null) {
      setIntent(intent)
      bind(intent)
    }
  }

  @Deprecated("Deliberately swallowed: the alarm may not be dismissed with the back gesture.")
  override fun onBackPressed() {
    // No-op by design.
  }

  private fun bind(intent: Intent) {
    val id = intent.getStringExtra(AlarmSchedulerRingService.EXTRA_ALARM_ID)
    val stored = id?.let { AlarmSchedulerStore.alarm(this, it) }
    if (id == null || stored == null) {
      finish()
      return
    }
    alarmId = id
    options = AlarmSchedulerOptions.fromJson(
      stored.optJSONObject("options"),
      stored.optString("title", "Alarm"),
      id
    )
    setContentView(buildContentView(stored.optString("title", "Alarm")))
  }

  private fun showOverLockScreen() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
      setShowWhenLocked(true)
      setTurnScreenOn(true)
      getSystemService(KeyguardManager::class.java)?.requestDismissKeyguard(this, null)
    } else {
      @Suppress("DEPRECATION")
      window.addFlags(
        WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
          WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
          WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
      )
    }
    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
  }

  private fun buildContentView(title: String): View {
    val resolved = options
    val root = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      gravity = Gravity.CENTER
      setBackgroundColor(Color.BLACK)
      setPadding(dp(32), dp(48), dp(32), dp(48))
    }

    root.addView(
      TextView(this).apply {
        text = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 64f)
        typeface = Typeface.create("sans-serif-light", Typeface.NORMAL)
        gravity = Gravity.CENTER
      }
    )

    root.addView(
      TextView(this).apply {
        text = resolved?.alertTitle?.takeIf { it.isNotBlank() } ?: title
        setTextColor(Color.WHITE)
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
        gravity = Gravity.CENTER
        setPadding(0, dp(12), 0, 0)
      }
    )

    resolved?.alertBody?.takeIf { it.isNotBlank() && it != "Alarm" }?.let { body ->
      root.addView(
        TextView(this).apply {
          text = body
          setTextColor(Color.parseColor("#9E9E9E"))
          setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
          gravity = Gravity.CENTER
          setPadding(0, dp(8), 0, 0)
        }
      )
    }

    root.addView(
      primaryButton(resolved?.secondaryButtonTitle ?: "Open app") { openApp() },
      LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56)).apply {
        topMargin = dp(48)
      }
    )

    if (resolved?.alertActionMode != ALERT_ACTION_MODE_OPEN_APP_ONLY) {
      root.addView(
        secondaryButton(resolved?.stopButtonTitle ?: "Stop") { stopAlarm() },
        LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, dp(56)).apply {
          topMargin = dp(12)
        }
      )
    }

    return root
  }

  private fun primaryButton(label: String, onClick: () -> Unit): Button = Button(this).apply {
    text = label
    isAllCaps = false
    setTextColor(Color.BLACK)
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
    background = GradientDrawable().apply {
      cornerRadius = dp(28).toFloat()
      setColor(Color.WHITE)
    }
    setOnClickListener { onClick() }
  }

  private fun secondaryButton(label: String, onClick: () -> Unit): Button = Button(this).apply {
    text = label
    isAllCaps = false
    setTextColor(Color.WHITE)
    setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
    background = GradientDrawable().apply {
      cornerRadius = dp(28).toFloat()
      setColor(Color.TRANSPARENT)
      setStroke(dp(1), Color.parseColor("#3D3D3D"))
    }
    setOnClickListener { onClick() }
  }

  private fun openApp() {
    val id = alarmId ?: return
    // The service keeps ringing: only the app's own completeNativeAlarmAsync() call ends it.
    startService(
      Intent(this, AlarmSchedulerRingService::class.java).apply {
        action = AlarmSchedulerRingService.ACTION_OPEN
        putExtra(AlarmSchedulerRingService.EXTRA_ALARM_ID, id)
      }
    )
    finish()
  }

  private fun stopAlarm() {
    val id = alarmId ?: return
    startService(
      Intent(this, AlarmSchedulerRingService::class.java).apply {
        action = AlarmSchedulerRingService.ACTION_STOP
        putExtra(AlarmSchedulerRingService.EXTRA_ALARM_ID, id)
      }
    )
    finish()
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

  companion object {
    fun intent(context: Context, alarmId: String): Intent {
      return Intent(context, AlarmSchedulerRingActivity::class.java).apply {
        action = Intent.ACTION_MAIN
        data = android.net.Uri.parse("alarm-scheduler-ring://$alarmId")
        putExtra(AlarmSchedulerRingService.EXTRA_ALARM_ID, alarmId)
        addFlags(
          Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_SINGLE_TOP or
            Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or
            Intent.FLAG_ACTIVITY_NO_USER_ACTION
        )
      }
    }
  }
}
