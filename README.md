# react-native-alarm-scheduler

Native alarm scheduling for React Native and Expo apps with Android exact alarms and iOS AlarmKit support.

`react-native-alarm-scheduler` is an Expo Modules API package for apps that need user-visible alarms, not just delayed background work. It exposes a small TypeScript API for checking alarm permissions, scheduling app-owned alarms, listing/canceling scheduled alarms, and opening native alarm surfaces where the operating system allows it.

## Features

- Android alarm scheduling through `AlarmManager.setAlarmClock`.
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
| Schedule an app-owned alarm | ✅ | ✅ | `scheduleAlarmAsync()` |
| Set native alarm sound | ❌ | ✅ | `ios.soundName` |
| Cancel an app-owned alarm | ✅ | ✅ | `cancelAlarmAsync(id)` |
| List app-owned alarms | ✅ | ✅ | `getScheduledAlarmsAsync()` |
| Read current alarm context | ❌ | ✅ | `getCurrentAlarmContextAsync()` |
| Read native alarm actions | ❌ | ✅ | `getPendingAlarmActionsAsync()` |
| Schedule/cancel a native backup alarm | ❌ | ✅ | `scheduleNativeAlarmBackupAsync()`, `cancelNativeAlarmBackupAsync()` |
| Create an alarm in the system Clock app | ✅ | ❌ | `setSystemAlarmAsync()` |
| Open the system alarm app | ✅ | ❌ | `openSystemAlarmAppAsync()` |
| Fire JS event when an alarm triggers | ✅ | ✅ | `onAlarmTriggered` |
| Web support | ❌ | ❌ | Explicit unavailable/no-op behavior |

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
| `iosAlarmSounds` | `string[]` | `[]` | Adds custom sound files to the iOS app bundle Resources build phase so AlarmKit can resolve them by filename. |

The plugin also enables `NSSupportsLiveActivities` for iOS AlarmKit intents and adds `com.android.alarm.permission.SET_ALARM` for Android system Clock alarm intents.

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
};
```

On Android, `canScheduleExactAlarms` reflects whether exact alarm scheduling is currently allowed. On iOS, it is `true` only when AlarmKit is available and authorized.

### `requestPermissionsAsync()`

Requests or opens the native permission surface where possible, then returns `AlarmPermissionResponse`.

On Android 12+, this opens the exact alarm settings screen if exact alarms are not currently allowed. On iOS 26+, this requests AlarmKit authorization.

### `openAlarmSettingsAsync()`

Opens the relevant alarm or app settings screen and returns whether the open action was started.

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
- iOS presentation options customize AlarmKit text only. They are not Android-style launch intents and do not force a React Native route.
- `ios.soundName` maps to AlarmKit's `AlertConfiguration.AlertSound.named(soundName)`. Omit it to use the system default sound. The sound name should be the exact bundled filename, including the extension, for example `bollywood-alarm.mp3`. In Expo apps, add the file path to the config plugin's `iosAlarmSounds` array so prebuild adds it to the iOS app bundle.
- `ios.alertActionMode: 'openMissionOnly'` prefers AlarmKit's newer secondary-only alert presentation when the runtime supports it. This omits the package-configured stop button and makes the secondary button the visible app action.
- `ios.stopIntentBehavior: 'recordOnly'` installs a built-in AlarmKit App Intent that records a `nativeStop` action when the system stop control is pressed.
- `ios.stopIntentBehavior: 'openApp'` records `nativeStop` and asks iOS to foreground the app immediately. The action record includes `foregroundRequested: true`; iOS does not provide a reliable success callback to the package.
- `ios.stopIntentBehavior: 'rescheduleImmediate'` records `nativeStop`, asks iOS to foreground the app, and attempts to schedule a short backup AlarmKit timer until JS calls `completeNativeAlarmAsync(alarmId)` or `clearBypassAsync(alarmId)`. Backup alarms use a deterministic native UUID derived from the original logical `alarmId`, so each re-arm cancels/replaces the previous backup instead of accumulating retry alarms.
- `ios.secondaryButtonBehavior: 'openApp'` installs a built-in AlarmKit App Intent that records `secondaryOpen` and asks iOS to open the app. Use `recordOnly` to record without foregrounding, or `none` to omit the secondary intent.
- AlarmKit may still expose system-owned close/stop affordances that do not invoke package App Intents. Use `getNativeAlarmDebugStateAsync(alarmId)` to inspect which alert initializer and buttons were used, and treat strict completion enforcement as limited by public AlarmKit APIs.

### `cancelAlarmAsync(id)`

Cancels an app-owned alarm by id. Returns `true` when a native or stored alarm was removed.

### `getScheduledAlarmsAsync()`

Returns the app-owned alarms stored by this module.

### `getCurrentAlarmContextAsync()`

Returns iOS alarm context for app launch or resume routing:

```ts
type AlarmContext = {
  id: string;
  metadata?: Record<string, string | number | boolean>;
  state?: 'scheduled' | 'alerting' | 'countdown' | 'paused';
  nativeAlarmId?: string;
};
```

On iOS 26+, this reads AlarmKit alarms owned by the app and joins them with metadata stored by this package. If the active native alarm is the deterministic backup timer, `id` remains the original logical alarm id and `nativeAlarmId` contains the backup UUID. If a one-shot alarm recently fired and AlarmKit already removed it from the daemon store, the package can still return the stored metadata for a short recovery window. On Android and Web this returns `null`.

### `getPendingAlarmActionsAsync()`

Returns native AlarmKit action records that happened while JS may not have been running:

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
};
```

`nativeStop` means the user pressed the system alarm stop control. Treat it as a bypass signal, not as successful completion.

### `getPendingNativeAlarmHandoffAsync()`

iOS only. Returns the latest native AlarmKit intent handoff recorded by the package, or `null` if none exists. This is a single durable handoff slot written directly by the native App Intent before JS listeners run, and is useful for app-launch routing:

```ts
const handoff = await ExpoAlarm.getPendingNativeAlarmHandoffAsync();

if (handoff?.action === 'nativeStop' || handoff?.action === 'secondaryOpen') {
  await ExpoAlarm.scheduleNativeAlarmBackupAsync(handoff.alarmId, 0.1);
  // route to your alarm handling UI
}
```

Use `clearPendingNativeAlarmHandoffAsync()` after your app has consumed the handoff.

### `clearPendingNativeAlarmHandoffAsync()`

Clears the durable native handoff slot. This does not clear the full action history returned by `getPendingAlarmActionsAsync()`.

### `clearPendingAlarmActionsAsync(ids?)`

Clears pending native action records. Pass action record `id` values to clear specific records, or omit `ids` to clear all records.

### `completeNativeAlarmAsync(alarmId)`

Marks the native alarm flow complete for `rescheduleImmediate`. Call this only after the user satisfies your app's completion condition. This stops future native stop intents from scheduling backup alarms for that `alarmId`, cancels the original native alarm when active, cancels the deterministic backup alarm and any legacy tracked retry alarms for that logical alarm id, and clears pending native action records for that alarm.

### `scheduleNativeAlarmBackupAsync(alarmId, delaySeconds?)`

iOS 26+ only. Schedules a short AlarmKit backup timer for an existing logical alarm id and returns:

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

iOS 26+ only. Cancels the deterministic backup timer for a logical alarm id and removes any legacy retry ids tracked by older package versions.

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
  alertInitializer?: 'secondaryOnly' | 'legacyStopButton';
  runtimeSupportsSecondaryOnlyAlert?: boolean;
  sound?: 'default' | 'named';
  soundName?: string;
};
```

If `alertActionMode` is `openMissionOnly` but `alertInitializer` is `legacyStopButton`, the runtime required the legacy stop-button presentation and the package cannot remove that AlarmKit stop affordance.

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

Currently Android shows a native notification when an app-owned alarm fires. The event is declared for API stability; delivery to a running JS runtime depends on app process state.

## Android behavior

Android exact alarm behavior depends on OS version, target SDK, user settings, and Play policy. The module checks `canScheduleExactAlarms()` before reporting alarm capability and uses `setAlarmClock()` for user-visible alarm semantics.

If exact alarms are denied, call `requestPermissionsAsync()` or `openAlarmSettingsAsync()` and ask the user to enable Alarms & reminders for your app.

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
