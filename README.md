# expo-alarm

Native alarm management for Expo apps with Android exact alarms and iOS AlarmKit support.

`expo-alarm` is an Expo Modules API package for apps that need user-visible alarms, not just delayed background work. It exposes a small TypeScript API for checking alarm permissions, scheduling app-owned alarms, listing/canceling scheduled alarms, and opening native alarm surfaces where the operating system allows it.

## Features

- Android alarm scheduling through `AlarmManager.setAlarmClock`.
- Android system Clock integration through `AlarmClock.ACTION_SET_ALARM` and `AlarmClock.ACTION_SHOW_ALARMS`.
- iOS native alarm scheduling through AlarmKit on iOS 26+.
- Config plugin for Android permissions and `NSAlarmKitUsageDescription`.
- Typed TypeScript API for Expo and React Native apps.
- Explicit unsupported behavior for platforms or OS versions that cannot schedule native alarms.

## Platform support

- Android: schedules app-owned exact alarms with `AlarmManager.setAlarmClock`, opens the system Clock alarm list, and can create system Clock alarms through `AlarmClock.ACTION_SET_ALARM`.
- iOS: schedules native alarms through AlarmKit when the app is built with the iOS 26 SDK and runs on iOS 26 or newer. Older iOS versions report `unavailable`.
- Web: no-op permission methods and explicit unsupported errors.

## Requirements

- Expo app with native prebuild support.
- Android API 24+.
- iOS 15.1+ for package compatibility.
- iOS 26 SDK and iOS 26 runtime for actual AlarmKit scheduling.

This module uses native code, so it is not available inside Expo Go. Use a development build or a prebuilt native app.

## Install

While this repo is not published under your npm account, install it from GitHub:

```sh
npm install github:rajmaurya-dev/expo-alarm
```

After publishing under the final npm package name:

```sh
npm install expo-alarm
```

## Configure

Add the config plugin to your app config before running `expo prebuild`:

```json
{
  "expo": {
    "plugins": [
      [
        "expo-alarm",
        {
          "alarmKitUsageDescription": "Allow this app to schedule alarms.",
          "addExactAlarmPermission": true,
          "addNotificationPermission": true
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

The plugin also adds `com.android.alarm.permission.SET_ALARM` for Android system Clock alarm intents.

Then rebuild native projects:

```sh
npx expo prebuild
npx expo run:android
npx expo run:ios
```

## Usage

Schedule an app-owned alarm:

```ts
import ExpoAlarm from 'expo-alarm';

const permissions = await ExpoAlarm.requestPermissionsAsync();

if (permissions.canScheduleExactAlarms) {
  const alarm = await ExpoAlarm.scheduleAlarmAsync({
    hour: 7,
    minute: 30,
    title: 'Morning alarm',
    weekdays: [1, 2, 3, 4, 5],
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
};
```

Notes:

- `hour` uses 24-hour time from `0` to `23`.
- `minute` must be from `0` to `59`.
- `timestamp` is milliseconds since Unix epoch. If omitted, the module schedules the next matching `hour` and `minute`.
- Android accepts any string `id`.
- iOS AlarmKit requires `id` to be a UUID string when you provide one.

### `cancelAlarmAsync(id)`

Cancels an app-owned alarm by id. Returns `true` when a native or stored alarm was removed.

### `getScheduledAlarmsAsync()`

Returns the app-owned alarms stored by this module.

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

subscription.remove();
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

## Publishing

Before publishing, confirm the final npm package name. The unscoped `expo-alarm` package name already exists on npm, so publish under an owned scope or transfer/claim the desired package name.

Useful checks:

```sh
npm view expo-alarm name version
npm whoami
npm pack --dry-run
```
