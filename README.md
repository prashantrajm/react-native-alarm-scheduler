# expo-alarm

Native alarm management for Expo apps.

## Platform support

- Android: schedules app-owned exact alarms with `AlarmManager.setAlarmClock`, opens the system Clock alarm list, and can create system Clock alarms through `AlarmClock.ACTION_SET_ALARM`.
- iOS: schedules native alarms through AlarmKit when the app is built with the iOS 26 SDK and runs on iOS 26 or newer. Older iOS versions report `unavailable`.
- Web: no-op permission methods and explicit unsupported errors.

## Install

```sh
npm install expo-alarm
```

Add the config plugin before running `expo prebuild`:

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

## Usage

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

## API

- `getPermissionsAsync()`
- `requestPermissionsAsync()`
- `openAlarmSettingsAsync()`
- `scheduleAlarmAsync(alarm)`
- `cancelAlarmAsync(id)`
- `getScheduledAlarmsAsync()`
- `setSystemAlarmAsync(alarm)` Android only
- `openSystemAlarmAppAsync()` Android system Clock, best-effort iOS Clock URL
