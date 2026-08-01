# react-native-alarm-scheduler

Native alarm scheduling for React Native and Expo apps with Android exact alarms and iOS AlarmKit support.

`react-native-alarm-scheduler` is an Expo Modules API package for apps that need user-visible alarms, not just delayed background work. It exposes a small TypeScript API for checking alarm permissions, scheduling app-owned alarms, listing/canceling scheduled alarms, and opening native alarm surfaces where the operating system allows it.

## Features

- Android alarm scheduling through `AlarmManager.setAlarmClock`.
- Android full-screen lock-screen ringing UI backed by a foreground service, so a killed app still rings.
- Android looping alarm-stream playback with volume pinning, so volume keys cannot silence a ringing alarm.
- Android completion-gated alarms: nothing but `completeNativeAlarmAsync()` ends the ring in `openMissionOnly` mode.
- Android metadata, handoff and action records that survive a cold launch, mirroring the iOS AlarmKit flow.
- Android alarm restoration across reboots, app updates and clock changes.
- Android system Clock integration through `AlarmClock.ACTION_SET_ALARM` and `AlarmClock.ACTION_SHOW_ALARMS`.
- iOS native alarm scheduling through AlarmKit on iOS 26+.
- iOS AlarmKit metadata and presentation options for app-resolved alarm routing.
- iOS AlarmKit App Intent actions for native stop and secondary alarm buttons.
- iOS AlarmKit default or named custom alert sounds.
- iOS AlarmKit backup timer helpers for completion-gated alarm flows.
- Config plugin for Android permissions and `NSAlarmKitUsageDescription`.
- Typed TypeScript API for React Native and Expo apps.
- Explicit unsupported behavior for platforms or OS versions that cannot schedule native alarms.

## Platform support

| Capability | Android | iOS | Available in this package |
| --- | --- | --- | --- |
| Check alarm authorization/capability | ✅ | ✅ | `getPermissionsAsync()` |
| Request alarm authorization | ✅ | ✅ | `requestPermissionsAsync()` |
| Open alarm/app settings | ✅ | ✅ | `openAlarmSettingsAsync()` |
| Open full-screen intent settings | ✅ | ❌ | `openFullScreenIntentSettingsAsync()` |
| Schedule an app-owned alarm | ✅ | ✅ | `scheduleAlarmAsync()` |
| Set native alarm sound | ✅ | ✅ | `android.soundName` / `android.soundUri`, `ios.soundName` |
| Cancel an app-owned alarm | ✅ | ✅ | `cancelAlarmAsync(id)` |
| List app-owned alarms | ✅ | ✅ | `getScheduledAlarmsAsync()` |
| Ring on the lock screen until the app says stop | ✅ | ⚠️ | `alertActionMode: 'openMissionOnly'` |
| Read current alarm context | ✅ | ✅ | `getCurrentAlarmContextAsync()` |
| Read native alarm actions | ✅ | ✅ | `getPendingAlarmActionsAsync()` |
| Read the cold-launch handoff slot | ✅ | ✅ | `getPendingNativeAlarmHandoffAsync()` |
| Complete a completion-gated alarm | ✅ | ✅ | `completeNativeAlarmAsync()` |
| Schedule/cancel a native backup alarm | ✅ | ✅ | `scheduleNativeAlarmBackupAsync()`, `cancelNativeAlarmBackupAsync()` |
| Survive reboot | ✅ | ✅ | Automatic |
| Create an alarm in the system Clock app | ✅ | ❌ | `setSystemAlarmAsync()` |
| Open the system alarm app | ✅ | ❌ | `openSystemAlarmAppAsync()` |
| Fire JS event when an alarm triggers | ✅ | ✅ | `onAlarmTriggered` |
| Web support | ❌ | ❌ | Explicit unavailable/no-op behavior |

⚠️ On iOS the ringing surface belongs to AlarmKit, so the system may still expose a stop control the
package cannot remove; `stopIntentBehavior: 'rescheduleImmediate'` re-arms behind it. On Android the
package owns the ringing surface outright, so `openMissionOnly` genuinely has no exit.

## Requirements

- Expo app with native prebuild support.
- Android API 24+.
- iOS 15.1+ for package compatibility.
- iOS 26 SDK and iOS 26 runtime for actual AlarmKit scheduling.

This module uses native code, so it is not available inside Expo Go. Use a development build or a prebuilt native app.

For bare React Native apps, install and configure Expo Modules first, then install this package. Expo apps already include the required runtime.

## Install

```sh
npm install react-native-alarm-scheduler
```

## Configure

Add the config plugin to your app config before running `expo prebuild`:

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

Plugin options:

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `alarmKitUsageDescription` | `string` | `Allow this app to schedule alarms that can alert you at the selected time.` | Adds `NSAlarmKitUsageDescription` for iOS AlarmKit authorization. |
| `addExactAlarmPermission` | `boolean` | `true` | Adds `android.permission.SCHEDULE_EXACT_ALARM`. |
| `addNotificationPermission` | `boolean` | `true` | Adds `android.permission.POST_NOTIFICATIONS`. |
| `addUseExactAlarmPermission` | `boolean` | `false` | Adds `android.permission.USE_EXACT_ALARM`, which is granted without prompting the user. Google Play only allows it for apps whose core function is an alarm clock or calendar. |
| `iosAlarmSounds` | `string[]` | `[]` | Adds custom sound files to the iOS app bundle Resources build phase so AlarmKit can resolve them by filename. |

The plugin also enables `NSSupportsLiveActivities` for iOS AlarmKit intents and adds `com.android.alarm.permission.SET_ALARM` for Android system Clock alarm intents.

The package's own Android manifest contributes the permissions the ringing layer needs — `WAKE_LOCK`,
`VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_SPECIAL_USE`, `DISABLE_KEYGUARD`, `TURN_SCREEN_ON` — plus the ringing service,
the lock-screen ring activity, and the boot receiver. Nothing extra is required in your app config.

The foreground service is declared as `specialUse` with the subtype `alarm`. Play Console asks for a
short justification for that type; "the service plays the alarm and keeps the ringing UI alive until
the user completes the wake-up flow" is the honest one.

Then rebuild native projects:

```sh
npx expo prebuild
npx expo run:android
npx expo run:ios
```

## Usage

Schedule an app-owned alarm:

```ts
import ExpoAlarm from 'react-native-alarm-scheduler';

const permissions = await ExpoAlarm.requestPermissionsAsync();

if (permissions.canScheduleExactAlarms) {
  const alarm = await ExpoAlarm.scheduleAlarmAsync({
    hour: 7,
    minute: 30,
    title: 'Morning alarm',
    weekdays: [1, 2, 3, 4, 5],
    ios: {
      metadata: {
        route: 'alarm-detail',
      },
      alertTitle: 'Morning alarm',
      alertActionMode: 'openMissionOnly',
      secondaryButtonTitle: 'Open',
      stopIntentBehavior: 'rescheduleImmediate',
      secondaryButtonBehavior: 'openApp',
    },
  });

  await ExpoAlarm.cancelAlarmAsync(alarm.id);
}
```

Weekdays use ISO numbering: `1=Monday` through `7=Sunday`.

Schedule an alarm the user cannot dismiss without finishing something in your app:

```ts
await ExpoAlarm.scheduleAlarmAsync({
  id: alarmId, // must be a UUID string for iOS
  hour: 7,
  minute: 0,
  title: 'Wake up',
  ios: {
    metadata: { mission: 'math', difficulty: 'hard' },
    alertActionMode: 'openMissionOnly',
    secondaryButtonTitle: 'Start mission',
    stopIntentBehavior: 'rescheduleImmediate',
  },
  // Android inherits every shared field above; this block only adds Android-specific behavior.
  android: {
    launchUri: 'myapp://mission/alarm-ring',
    maxRingDurationSeconds: 0,
  },
});
```

Then, on launch and on resume, route from whichever native record exists:

```ts
const handoff = await ExpoAlarm.getPendingNativeAlarmHandoffAsync();
const context = handoff ? null : await ExpoAlarm.getCurrentAlarmContextAsync();
const alarmId = handoff?.alarmId ?? context?.id;

if (alarmId) {
  router.replace(`/mission/${alarmId}`);
  await ExpoAlarm.clearPendingNativeAlarmHandoffAsync();
}
```

And only once the user actually finishes:

```ts
await ExpoAlarm.completeNativeAlarmAsync(alarmId);
await ExpoAlarm.cancelAlarmAsync(alarmId); // then reschedule if the alarm repeats
```

Open Android's system alarm UI:

```ts
await ExpoAlarm.openSystemAlarmAppAsync();
```

Create a system Clock alarm on Android:

```ts
await ExpoAlarm.setSystemAlarmAsync({
  hour: 8,
  minute: 0,
  title: 'Leave for work',
  weekdays: [1, 2, 3, 4, 5],
  showUi: true,
});
```

List and cancel app-owned alarms:

```ts
const alarms = await ExpoAlarm.getScheduledAlarmsAsync();

for (const alarm of alarms) {
  await ExpoAlarm.cancelAlarmAsync(alarm.id);
}
```

## API

### `getPermissionsAsync()`

Returns the current alarm capability state:

```ts
type AlarmPermissionResponse = {
  platform: 'android' | 'ios';
  status: 'authorized' | 'denied' | 'notDetermined' | 'unavailable' | 'unknown';
  canScheduleExactAlarms: boolean;
  canOpenSettings: boolean;
  canUseFullScreenIntent?: boolean;
  canPostNotifications?: boolean;
};
```

`canUseFullScreenIntent` is Android 14+ only: the alarm still rings without it, but it surfaces as a
heads-up notification instead of taking over a locked screen. Send the user to
`openFullScreenIntentSettingsAsync()` to grant it. Both extra fields are `true` on older Android
versions and on iOS.

On Android, `canScheduleExactAlarms` reflects whether exact alarm scheduling is currently allowed. On iOS, it is `true` only when AlarmKit is available and authorized.

### `requestPermissionsAsync()`

Requests or opens the native permission surface where possible, then returns `AlarmPermissionResponse`.

On Android 12+, this opens the exact alarm settings screen if exact alarms are not currently allowed. On iOS 26+, this requests AlarmKit authorization.

### `openAlarmSettingsAsync()`

Opens the relevant alarm or app settings screen and returns whether the open action was started.

### `openFullScreenIntentSettingsAsync()`

Android 14+ only. Opens the per-app "Full screen notifications" settings screen. Returns `false` on
older Android versions, on iOS, on web, and when no matching settings activity exists.

### `scheduleAlarmAsync(alarm)`

Schedules an app-owned native alarm and returns the stored alarm.

```ts
type AlarmScheduleInput = {
  id?: string;
  hour: number;
  minute: number;
  title?: string;
  weekdays?: AlarmWeekday[];
  timestamp?: number;
  showUi?: boolean;
  ios?: {
    metadata?: Record<string, string | number | boolean>;
    alertTitle?: string;
    alertActionMode?: 'default' | 'openMissionOnly';
    stopButtonTitle?: string;
    secondaryButtonTitle?: string;
    countdownTitle?: string;
    stopIntentBehavior?: 'recordOnly' | 'openApp' | 'rescheduleImmediate';
    secondaryButtonBehavior?: 'openApp' | 'recordOnly' | 'none';
    soundName?: string;
  };
  android?: {
    metadata?: Record<string, string | number | boolean>;
    alertTitle?: string;
    alertBody?: string;
    alertActionMode?: 'default' | 'openMissionOnly';
    stopButtonTitle?: string;
    secondaryButtonTitle?: string;
    stopIntentBehavior?: 'recordOnly' | 'openApp' | 'rescheduleImmediate';
    secondaryButtonBehavior?: 'openApp' | 'recordOnly' | 'none';
    soundName?: string;
    soundUri?: string;
    vibrate?: boolean;
    enforceVolume?: boolean;
    restoreVolume?: boolean;
    volume?: number;
    fullScreen?: boolean;
    fullScreenTarget?: 'native' | 'app';
    launchUri?: string;
    maxRingDurationSeconds?: number;
    backupDelaySeconds?: number;
  };
};

type AlarmWeekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

type ScheduledAlarm = {
  id: string;
  hour: number;
  minute: number;
  title: string;
  weekdays: AlarmWeekday[];
  timestamp: number;
  platform: 'android' | 'ios';
  metadata?: Record<string, string | number | boolean>;
};
```

Notes:

- `hour` uses 24-hour time from `0` to `23`.
- `minute` must be from `0` to `59`.
- `timestamp` is milliseconds since Unix epoch. If omitted, the module schedules the next matching `hour` and `minute`.
- Android accepts any string `id`.
- iOS AlarmKit requires `id` to be a UUID string when you provide one.
- `ios.metadata` is stored by the package and included in AlarmKit metadata. The package always adds `alarmId` and `title`.
- Every `android` option that means the same thing as an `ios` option — `metadata`, `alertTitle`, `alertActionMode`, `stopButtonTitle`, `secondaryButtonTitle`, `stopIntentBehavior`, `secondaryButtonBehavior`, `soundName` — falls back to the `ios` value when omitted. An app already written against the AlarmKit flow gets the same behavior on Android without passing an `android` block at all. Set `android` fields only where the platforms should differ.
- iOS presentation options customize AlarmKit text only. They are not Android-style launch intents and do not force a React Native route.
- `ios.soundName` maps to AlarmKit's `AlertConfiguration.AlertSound.named(soundName)`. Omit it to use the system default sound. The sound name should be the exact bundled filename, including the extension, for example `bollywood-alarm.mp3`. In Expo apps, add the file path to the config plugin's `iosAlarmSounds` array so prebuild adds it to the iOS app bundle.
- `ios.alertActionMode: 'openMissionOnly'` prefers AlarmKit's newer secondary-only alert presentation when the runtime supports it. This omits the package-configured stop button and makes the secondary button the visible app action.
- `ios.stopIntentBehavior: 'recordOnly'` installs a built-in AlarmKit App Intent that records a `nativeStop` action when the system stop control is pressed.
- `ios.stopIntentBehavior: 'openApp'` records `nativeStop` and asks iOS to foreground the app immediately. The action record includes `foregroundRequested: true`; iOS does not provide a reliable success callback to the package.
- `ios.stopIntentBehavior: 'rescheduleImmediate'` records `nativeStop`, asks iOS to foreground the app, and attempts to schedule a short backup AlarmKit timer until JS calls `completeNativeAlarmAsync(alarmId)` or `clearBypassAsync(alarmId)`. Backup alarms use a deterministic native UUID derived from the original logical `alarmId`, so each re-arm cancels/replaces the previous backup instead of accumulating retry alarms.
- `ios.secondaryButtonBehavior: 'openApp'` installs a built-in AlarmKit App Intent that records `secondaryOpen` and asks iOS to open the app. Use `recordOnly` to record without foregrounding, or `none` to omit the secondary intent.
- AlarmKit may still expose system-owned close/stop affordances that do not invoke package App Intents. Use `getNativeAlarmDebugStateAsync(alarmId)` to inspect which alert initializer and buttons were used, and treat strict completion enforcement as limited by public AlarmKit APIs.
- `android.alertActionMode: 'openMissionOnly'` removes the stop button from both the ringing screen and the notification. The only way out is the hand-off button, which opens your app while the alarm keeps ringing; the alarm stops when your app calls `completeNativeAlarmAsync(alarmId)`. Back gestures are swallowed and the notification is ongoing, so it cannot be swiped away.
- `android.stopIntentBehavior: 'rescheduleImmediate'` arms a backup alarm whenever the user does stop without completing — including when a ring hits `maxRingDurationSeconds`. Backup ids are deterministic (`<alarmId>#backup`), so re-arming replaces rather than accumulates.
- `android.soundName` resolves a file in `android/app/src/main/res/raw` (extension optional); `android.soundUri` accepts any content or resource URI and wins over `soundName`. If neither resolves, the package falls back to the system alarm ringtone. Playback loops on `STREAM_ALARM`, which ignores the ringer and Do Not Disturb.
- `android.enforceVolume` (default `true`) pins the alarm stream at `android.volume` for the duration of the ring and re-raises it whenever anything lowers it, then restores the user's original level unless `restoreVolume` is `false`.
- `android.fullScreenTarget: 'native'` (default) shows the package's own lock-screen ring screen, which appears instantly even from a cold start. Use `'app'` only if your own launch activity sets `showWhenLocked`, otherwise it opens behind the keyguard.
- `android.launchUri` is the deep link opened when the user hands off, for example `'myapp://mission/alarm-ring'`. `{alarmId}` is substituted when present; otherwise `?alarmId=` is appended.
- `android.maxRingDurationSeconds` (default 300) time-boxes the ring for battery's sake. Set `0` to ring until the app completes the alarm.

### `cancelAlarmAsync(id)`

Cancels an app-owned alarm by id. Returns `true` when a native or stored alarm was removed.

### `getScheduledAlarmsAsync()`

Returns the app-owned alarms stored by this module.

### `getCurrentAlarmContextAsync()`

Returns alarm context for app launch or resume routing:

```ts
type AlarmContext = {
  id: string;
  metadata?: Record<string, string | number | boolean>;
  state?: 'scheduled' | 'alerting' | 'countdown' | 'paused';
  nativeAlarmId?: string;
};
```

On iOS 26+, this reads AlarmKit alarms owned by the app and joins them with metadata stored by this package. If the active native alarm is the deterministic backup timer, `id` remains the original logical alarm id and `nativeAlarmId` contains the backup UUID. If a one-shot alarm recently fired and AlarmKit already removed it from the daemon store, the package can still return the stored metadata for a short recovery window.

On Android, this returns the currently ringing alarm with `state: 'alerting'`, falling back to a
one-shot alarm that fired within the last hour and was never completed — the same recovery window as
iOS. On Web this returns `null`.

### `getPendingAlarmActionsAsync()`

Returns native action records that happened while JS may not have been running — AlarmKit App Intents
on iOS, ringing-service events on Android:

```ts
type AlarmAction = {
  id: string;
  alarmId: string;
  action: 'nativeStop' | 'secondaryOpen' | 'snooze' | 'dismiss';
  timestamp: number;
  foregroundRequested?: boolean;
  rescheduled?: boolean;
  rescheduledAlarmId?: string;
  retryScheduledFor?: number;
  backupAlarmId?: string;
  backupScheduledFor?: number;
  backupDelaySeconds?: number;
  trigger?: boolean;
  timedOut?: boolean;
};
```

`nativeStop` means the user pressed the system alarm stop control. Treat it as a bypass signal, not as successful completion.

On Android, `secondaryOpen` records carry `trigger: true` when they were written by the alarm firing
rather than by a user tap, and `dismiss` records carry `timedOut: true` when the ring hit
`maxRingDurationSeconds`.

### `getPendingNativeAlarmHandoffAsync()`

Returns the latest native handoff recorded by the package, or `null` if none exists. This is a single
durable slot written by native code before any JS listener runs, which makes it the right source for
app-launch routing:

```ts
const handoff = await ExpoAlarm.getPendingNativeAlarmHandoffAsync();

if (handoff?.action === 'nativeStop' || handoff?.action === 'secondaryOpen') {
  await ExpoAlarm.scheduleNativeAlarmBackupAsync(handoff.alarmId, 0.1);
  // route to your alarm handling UI
}
```

Use `clearPendingNativeAlarmHandoffAsync()` after your app has consumed the handoff.

On iOS the slot is written by the AlarmKit App Intent when the user presses a button. On Android it
is written the moment the alarm starts ringing, so a cold-launched app can route straight to its
alarm UI without waiting for a JS event.

### `clearPendingNativeAlarmHandoffAsync()`

Clears the durable native handoff slot. This does not clear the full action history returned by `getPendingAlarmActionsAsync()`.

### `clearPendingAlarmActionsAsync(ids?)`

Clears pending native action records. Pass action record `id` values to clear specific records, or omit `ids` to clear all records.

### `completeNativeAlarmAsync(alarmId)`

Marks the native alarm flow complete for `rescheduleImmediate`. Call this only after the user satisfies your app's completion condition. This stops future native stop intents from scheduling backup alarms for that `alarmId`, cancels the original native alarm when active, cancels the deterministic backup alarm and any legacy tracked retry alarms for that logical alarm id, and clears pending native action records for that alarm.

On Android this is also what silences the ringing service, so it is mandatory rather than advisory:
with `alertActionMode: 'openMissionOnly'` the alarm keeps playing until this call lands.

### `scheduleNativeAlarmBackupAsync(alarmId, delaySeconds?)`

Schedules a short backup alarm for an existing logical alarm id — an AlarmKit timer on iOS 26+, an
exact `setAlarmClock` on Android — and returns:

```ts
type NativeAlarmBackupResult = {
  alarmId: string;
  backupAlarmId: string;
  scheduled: boolean;
  scheduledFor?: number;
  delaySeconds: number;
};
```

The backup id is deterministic for the primary alarm id. Calling this repeatedly cancels/replaces the same backup timer. This is useful when your app processes a native alarm handoff from `getPendingAlarmActionsAsync()` or finds an alerting alarm from `getCurrentAlarmContextAsync()` and needs to re-arm before presenting app UI.

### `cancelNativeAlarmBackupAsync(alarmId)`

Cancels the deterministic backup timer for a logical alarm id and removes any legacy retry ids tracked by older package versions.

### `clearBypassAsync(alarmId)`

Clears the completion marker for an alarm id, allowing `rescheduleImmediate` retries again for that alarm id. Prefer `resetNativeAlarmCompletionAsync(alarmId)` for clearer naming.

### `resetNativeAlarmCompletionAsync(alarmId)`

Alias for `clearBypassAsync(alarmId)` with clearer semantics.

### `getNativeAlarmDebugStateAsync(alarmId)`

Returns native retry/debug state:

```ts
type NativeAlarmDebugState = {
  alarmId: string;
  isComplete: boolean;
  activeRetryAlarmIds: string[];
  pendingActions: AlarmAction[];
  pendingHandoff?: AlarmAction | null;
  intentDebugCounts?: Record<string, number>;
  currentContext: AlarmContext | null;
  alertActionMode?: 'default' | 'openMissionOnly';
  stopButtonIncluded?: boolean;
  secondaryButtonIncluded?: boolean;
  secondaryButtonBehavior?: 'openApp' | 'recordOnly' | 'none';
  stopIntentBehavior?: 'recordOnly' | 'openApp' | 'rescheduleImmediate';
  alertInitializer?: 'secondaryOnly' | 'legacyStopButton' | 'androidRingService';
  runtimeSupportsSecondaryOnlyAlert?: boolean;
  sound?: 'default' | 'named';
  soundName?: string;
  isRinging?: boolean;
  isScheduled?: boolean;
  canUseFullScreenIntent?: boolean;
  canScheduleExactAlarms?: boolean;
};
```

If `alertActionMode` is `openMissionOnly` but `alertInitializer` is `legacyStopButton`, the runtime required the legacy stop-button presentation and the package cannot remove that AlarmKit stop affordance.

On Android `alertInitializer` is always `androidRingService`, and `isRinging`, `isScheduled`,
`canUseFullScreenIntent` and `canScheduleExactAlarms` describe the live state of the ringing service
and the two grants the ringing UI depends on.

### `setSystemAlarmAsync(alarm)`

Android only. Sends an `AlarmClock.ACTION_SET_ALARM` intent to create an alarm in the user's Clock app. Returns `false` if no compatible Clock activity is available.

iOS does not expose a public API for creating alarms in the system Clock app, so this method throws on iOS.

### `openSystemAlarmAppAsync()`

Opens the Android system Clock alarm screen. On iOS this uses a best-effort Clock URL and may return `false` or do nothing depending on the OS.

## Events

```ts
const subscription = ExpoAlarm.addListener('onAlarmTriggered', (alarm) => {
  console.log(alarm);
});

const actionSubscription = ExpoAlarm.addListener('onAlarmAction', (action) => {
  console.log(action);
});

const stateSubscription = ExpoAlarm.addListener('onAlarmStateChange', (event) => {
  console.log(event);
});

subscription.remove();
actionSubscription.remove();
stateSubscription.remove();
```

Events are delivered only when a JS runtime happens to be alive. Everything they carry is also
persisted natively, so the reliable pattern on both platforms is: handle the event if it arrives, and
reconcile from `getPendingNativeAlarmHandoffAsync()`, `getPendingAlarmActionsAsync()` and
`getCurrentAlarmContextAsync()` on every launch and foreground.

## Android behavior

Android exact alarm behavior depends on OS version, target SDK, user settings, and Play policy. The module checks `canScheduleExactAlarms()` before reporting alarm capability and uses `setAlarmClock()` for user-visible alarm semantics.

If exact alarms are denied, call `requestPermissionsAsync()` or `openAlarmSettingsAsync()` and ask the user to enable Alarms & reminders for your app. **Treat this as required, not optional.** Without it the package falls back to `setAndAllowWhileIdle()`, which loses more than timing accuracy: Android only exempts *exact* alarms from the background foreground-service restriction, so the ringing service cannot start either. The package then degrades again to a full-screen-intent notification that rings through its own channel — audible, but no wake lock and no guaranteed screen takeover.

### What happens when an alarm fires

1. `AlarmManager` delivers the broadcast to the package's receiver, even in Doze. Repeating alarms re-arm their next occurrence immediately.
2. The receiver starts a foreground service, which takes a wake lock, pins the alarm stream volume, and starts looping the alarm sound. The service outlives the receiver's 10-second window and does not need a JS runtime.
3. The service posts an ongoing, full-screen-intent notification and launches the ringing screen directly — `setAlarmClock()` grants the background activity-start allowance that makes this legal.
4. Before anything else, the handoff and action records are written to disk, so a cold-launched app can route correctly no matter how it was opened.
5. The alarm keeps ringing until `completeNativeAlarmAsync(alarmId)`, an explicit stop, or `maxRingDurationSeconds`.

### Reboots, updates and clock changes

Alarms are stored natively and re-armed on `BOOT_COMPLETED`, `MY_PACKAGE_REPLACED`, `TIME_SET` and `TIMEZONE_CHANGED`. One-shot alarms whose time passed while the device was off are dropped, matching the system Clock app.

### Android 14+ full-screen intents

Android 14 gates full-screen notifications behind a per-app grant. Apps whose declared category is an alarm clock get it by default; others must ask. Check `canUseFullScreenIntent` from `getPermissionsAsync()` and send the user to `openFullScreenIntentSettingsAsync()`. Without the grant the alarm still rings and still posts a heads-up notification — it just does not take over a locked screen.

### OEM battery optimization

Aggressive OEM power managers (Xiaomi, Oppo, Vivo, Samsung, Huawei) can kill background processes in
ways `setAlarmClock` does not fully protect against. There is no API that fixes this; the standard
mitigation is to ask users on those devices to disable battery optimization for your app and to allow
autostart.

## iOS behavior

iOS alarm scheduling uses AlarmKit. The app must:

- Build with an SDK that includes AlarmKit.
- Run on iOS 26 or newer.
- Include a non-empty `NSAlarmKitUsageDescription`.
- Receive user authorization through `requestPermissionsAsync()`.

Older iOS versions return `status: 'unavailable'`.

AlarmKit does not expose Android-style `Intent` or `PendingIntent` launch routing. For route-specific behavior, put route context such as `alarmId` or a screen name in `ios.metadata`, then call `getCurrentAlarmContextAsync()` and `getPendingAlarmActionsAsync()` on app launch or resume and navigate from JavaScript. Foreground listeners such as `onAlarmAction` and `onAlarmStateChange` are best effort; apps should reconcile from the async getters after launch.

## Development

```sh
npm install
npm run build
npm run lint
npm run prepublishOnly
```

Run the example app:

```sh
cd example
npm install
npm run android
npm run ios
```
