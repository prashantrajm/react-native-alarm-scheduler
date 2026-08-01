# Platform notes

Deep behavior notes for `react-native-alarm-scheduler`. For the method-by-method
reference see the [API documentation](https://rajmauryafr.github.io/react-native-alarm-scheduler/api.html).

## Config plugin options

```json
{
  "expo": {
    "plugins": [
      [
        "react-native-alarm-scheduler",
        {
          "alarmKitUsageDescription": "Allow this app to schedule alarms.",
          "addExactAlarmPermission": true,
          "addNotificationPermission": true,
          "iosAlarmSounds": ["./assets/audio/bollywood-alarm.mp3"]
        }
      ]
    ]
  }
}
```

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `alarmKitUsageDescription` | `string` | `Allow this app to schedule alarms that can alert you at the selected time.` | Adds `NSAlarmKitUsageDescription` for iOS AlarmKit authorization. |
| `addExactAlarmPermission` | `boolean` | `true` | Adds `android.permission.SCHEDULE_EXACT_ALARM`. |
| `addNotificationPermission` | `boolean` | `true` | Adds `android.permission.POST_NOTIFICATIONS`. |
| `addUseExactAlarmPermission` | `boolean` | `false` | Adds `android.permission.USE_EXACT_ALARM`, which is granted without prompting the user. Google Play only allows it for apps whose core function is an alarm clock or calendar. |
| `iosAlarmSounds` | `string[]` | `[]` | Adds custom sound files to the iOS app bundle Resources build phase so AlarmKit can resolve them by filename. |

The plugin also enables `NSSupportsLiveActivities` for iOS AlarmKit intents and adds
`com.android.alarm.permission.SET_ALARM` for Android system Clock alarm intents.

The package's own Android manifest contributes the permissions the ringing layer needs — `WAKE_LOCK`,
`VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_SPECIAL_USE`, `DISABLE_KEYGUARD`, `TURN_SCREEN_ON` — plus the ringing service,
the lock-screen ring activity, and the boot receiver. Nothing extra is required in your app config.

The foreground service is declared as `specialUse` with the subtype `alarm`. Play Console asks for a
short justification for that type; "the service plays the alarm and keeps the ringing UI alive until
the user completes the wake-up flow" is the honest one.

## Android behavior

Android exact alarm behavior depends on OS version, target SDK, user settings, and Play policy. The
module checks `canScheduleExactAlarms()` before reporting alarm capability and uses `setAlarmClock()`
for user-visible alarm semantics.

If exact alarms are denied, call `requestPermissionsAsync()` or `openAlarmSettingsAsync()` and ask the
user to enable Alarms & reminders for your app. **Treat this as required, not optional.** Without it
the package falls back to `setAndAllowWhileIdle()`, which loses more than timing accuracy: Android
only exempts *exact* alarms from the background foreground-service restriction, so the ringing service
cannot start either. The package then degrades again to a full-screen-intent notification that rings
through its own channel — audible, but no wake lock and no guaranteed screen takeover.

### What happens when an alarm fires

1. `AlarmManager` delivers the broadcast to the package's receiver, even in Doze. Repeating alarms re-arm their next occurrence immediately.
2. The receiver starts a foreground service, which takes a wake lock, pins the alarm stream volume, and starts looping the alarm sound. The service outlives the receiver's 10-second window and does not need a JS runtime.
3. The service posts an ongoing, full-screen-intent notification and launches the ringing screen directly — `setAlarmClock()` grants the background activity-start allowance that makes this legal.
4. Before anything else, the handoff and action records are written to disk, so a cold-launched app can route correctly no matter how it was opened.
5. The alarm keeps ringing until `completeNativeAlarmAsync(alarmId)`, an explicit stop, or `maxRingDurationSeconds`.

### Reboots, updates and clock changes

Alarms are stored natively and re-armed on `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_SET` and
`TIMEZONE_CHANGED`. One-shot alarms whose time passed while the device was off are dropped, matching
the system Clock app.

### Android 14+ full-screen intents

Android 14 gates full-screen notifications behind a per-app grant. Apps whose declared category is an
alarm clock get it by default; others must ask. Check `canUseFullScreenIntent` from
`getPermissionsAsync()` and send the user to `openFullScreenIntentSettingsAsync()`. Without the grant
the alarm still rings and still posts a heads-up notification — it just does not take over a locked
screen.

### OEM battery optimization

Aggressive OEM power managers (Xiaomi, Oppo, Vivo, Samsung, Huawei) can kill background processes in
ways `setAlarmClock` does not fully protect against. There is no API that fixes this; the standard
mitigation is to ask users on those devices to disable battery optimization for your app and to allow
autostart.

### Sound and volume

`android.soundName` resolves a file in `android/app/src/main/res/raw` (extension optional);
`android.soundUri` accepts any content or resource URI and wins over `soundName`. If neither resolves,
the package falls back to the system alarm ringtone. Playback loops on `STREAM_ALARM`, which ignores
the ringer and Do Not Disturb.

`android.enforceVolume` (default `true`) pins the alarm stream at `android.volume` for the duration of
the ring and re-raises it whenever anything lowers it, then restores the user's original level unless
`restoreVolume` is `false`.

### Ringing surface and handoff

- `android.fullScreenTarget: 'native'` (default) shows the package's own lock-screen ring screen, which appears instantly even from a cold start. Use `'app'` only if your own launch activity sets `showWhenLocked`, otherwise it opens behind the keyguard.
- `android.launchUri` is the deep link opened when the user hands off, for example `'myapp://mission/alarm-ring'`. `{alarmId}` is substituted when present; otherwise `?alarmId=` is appended.
- `android.maxRingDurationSeconds` (default 300) time-boxes the ring for battery's sake. Set `0` to ring until the app completes the alarm.
- `android.alertActionMode: 'openMissionOnly'` removes the stop button from both the ringing screen and the notification. The only way out is the hand-off button, which opens your app while the alarm keeps ringing; the alarm stops when your app calls `completeNativeAlarmAsync(alarmId)`. Back gestures are swallowed and the notification is ongoing, so it cannot be swiped away.
- `android.stopIntentBehavior: 'rescheduleImmediate'` arms a backup alarm whenever the user does stop without completing — including when a ring hits `maxRingDurationSeconds`. Backup ids are deterministic (`<alarmId>#backup`), so re-arming replaces rather than accumulates.

## iOS behavior

iOS alarm scheduling uses AlarmKit. The app must:

- Build with an SDK that includes AlarmKit.
- Run on iOS 26 or newer.
- Include a non-empty `NSAlarmKitUsageDescription`.
- Receive user authorization through `requestPermissionsAsync()`.

Older iOS versions return `status: 'unavailable'`.

AlarmKit does not expose Android-style `Intent` or `PendingIntent` launch routing. For route-specific
behavior, put route context such as `alarmId` or a screen name in `ios.metadata`, then call
`getCurrentAlarmContextAsync()` and `getPendingAlarmActionsAsync()` on app launch or resume and
navigate from JavaScript. Foreground listeners such as `onAlarmAction` and `onAlarmStateChange` are
best effort; apps should reconcile from the async getters after launch.

### Alert presentation

- `ios.alertActionMode: 'openMissionOnly'` prefers AlarmKit's newer secondary-only alert presentation when the runtime supports it. This omits the package-configured stop button and makes the secondary button the visible app action.
- `ios.stopIntentBehavior: 'recordOnly'` installs a built-in AlarmKit App Intent that records a `nativeStop` action when the system stop control is pressed.
- `ios.stopIntentBehavior: 'openApp'` records `nativeStop` and asks iOS to foreground the app immediately. The action record includes `foregroundRequested: true`; iOS does not provide a reliable success callback to the package.
- `ios.stopIntentBehavior: 'rescheduleImmediate'` records `nativeStop`, asks iOS to foreground the app, and attempts to schedule a short backup AlarmKit timer until JS calls `completeNativeAlarmAsync(alarmId)` or `resetNativeAlarmCompletionAsync(alarmId)`. Backup alarms use a deterministic native UUID derived from the original logical `alarmId`, so each re-arm cancels/replaces the previous backup instead of accumulating retry alarms.
- `ios.secondaryButtonBehavior: 'openApp'` installs a built-in AlarmKit App Intent that records `secondaryOpen` and asks iOS to open the app. Use `recordOnly` to record without foregrounding, or `none` to omit the secondary intent.
- AlarmKit may still expose system-owned close/stop affordances that do not invoke package App Intents. Use `getNativeAlarmDebugStateAsync(alarmId)` to inspect which alert initializer and buttons were used, and treat strict completion enforcement as limited by public AlarmKit APIs. If `alertActionMode` is `openMissionOnly` but `alertInitializer` is `legacyStopButton`, the runtime required the legacy stop-button presentation and the package cannot remove that AlarmKit stop affordance.

### Sound

`ios.soundName` maps to AlarmKit's `AlertConfiguration.AlertSound.named(soundName)`. Omit it to use
the system default sound. The sound name should be the exact bundled filename, including the
extension, for example `bollywood-alarm.mp3`. In Expo apps, add the file path to the config plugin's
`iosAlarmSounds` array so prebuild adds it to the iOS app bundle.
