# react-native-alarm-scheduler

[![npm version](https://img.shields.io/npm/v/react-native-alarm-scheduler.svg)](https://www.npmjs.com/package/react-native-alarm-scheduler)
[![license](https://img.shields.io/npm/l/react-native-alarm-scheduler.svg)](https://github.com/rajmauryafr/react-native-alarm-scheduler/blob/main/LICENSE)
![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios-lightgrey)

Real, user-visible alarms for React Native and Expo apps — not delayed background work.

Notification libraries schedule a notification and hope the device is awake to show it. This package
schedules an actual alarm: Android `AlarmManager.setAlarmClock` with a foreground service that keeps
ringing through Doze and a killed app, and iOS AlarmKit on iOS 26+. It also supports
**completion-gated alarms** — the ring does not stop until your app says the user has actually woken up.

## Features

- ⏰ **App-owned native alarms** on Android and iOS from one typed API.
- 🔒 **Completion gating** — with `openMissionOnly`, only `completeNativeAlarmAsync()` ends the ring.
- 📢 **Stays audible on Android** — loops on the alarm stream, ignoring the ringer and Do Not Disturb, and re-raises the volume when anything lowers it.
- 📱 **Full-screen lock-screen ringing UI** backed by a foreground service, so a killed app still rings.
- 🔁 **Survives reboots**, app updates, and clock/timezone changes.
- 🧭 **Cold-launch handoff records** written natively before any JS runs, so your app always knows why it opened.
- 🎵 **Custom alarm sounds** on both platforms, bundled by the config plugin.
- 🕐 **System Clock integration** on Android via `ACTION_SET_ALARM` and `ACTION_SHOW_ALARMS`.
- 🧩 **Expo config plugin** for permissions and `NSAlarmKitUsageDescription`.
- 🔷 **Fully typed** TypeScript API, with explicit unavailable behavior where the OS cannot schedule alarms.

## Documentation

📖 **[Documentation](https://react-native-alarm-scheduler.vercel.app)** — guides for scheduling, handoffs, and sounds.

- **[API reference](https://react-native-alarm-scheduler.vercel.app/api)** — every method, type, and event.
- **[Platform behavior](https://react-native-alarm-scheduler.vercel.app/platforms/android)** — Android ringing internals and iOS AlarmKit limits.
- **[Example app](https://github.com/rajmauryafr/react-native-alarm-scheduler/tree/main/example)** — a runnable Expo app exercising the full API.
- **[For AI agents](https://react-native-alarm-scheduler.vercel.app/ai)** — [`llms.txt`](https://react-native-alarm-scheduler.vercel.app/llms.txt), raw markdown per page, and a bundled agent skill.

## Requirements

- An Expo or bare React Native app with native prebuild support — this module uses native code, so it does **not** work in Expo Go.
- Android API 24+.
- iOS 15.1+ for compatibility; iOS 26 SDK and runtime for actual AlarmKit scheduling.

Bare React Native apps need [Expo Modules](https://docs.expo.dev/bare/installing-expo-modules/) installed first.

## Installation

```sh
npm install react-native-alarm-scheduler
```

Add the config plugin to your app config, then rebuild:

```json
{
  "expo": {
    "plugins": [
      [
        "react-native-alarm-scheduler",
        { "alarmKitUsageDescription": "Allow this app to schedule alarms." }
      ]
    ]
  }
}
```

```sh
npx expo prebuild
npx expo run:android
```

All plugin options are listed in the [installation docs](https://react-native-alarm-scheduler.vercel.app/installation#plugin-options).

## Usage

```ts
import ExpoAlarm from 'react-native-alarm-scheduler';

const permissions = await ExpoAlarm.requestPermissionsAsync();

if (permissions.canScheduleExactAlarms) {
  const alarm = await ExpoAlarm.scheduleAlarmAsync({
    hour: 7,
    minute: 30,
    title: 'Morning alarm',
    weekdays: [1, 2, 3, 4, 5], // ISO: 1 = Monday, 7 = Sunday
  });

  await ExpoAlarm.cancelAlarmAsync(alarm.id);
}
```

### An alarm the user cannot dismiss

Set `alertActionMode: 'openMissionOnly'` and the only way out is a button that opens your app while
the alarm keeps ringing:

```ts
await ExpoAlarm.scheduleAlarmAsync({
  id: alarmId, // must be a UUID string on iOS
  hour: 7,
  minute: 0,
  title: 'Wake up',
  ios: {
    metadata: { mission: 'math' },
    alertActionMode: 'openMissionOnly',
    secondaryButtonTitle: 'Start mission',
    stopIntentBehavior: 'rescheduleImmediate',
  },
  // Android inherits every shared iOS field; set android only where platforms differ.
  android: { launchUri: 'myapp://mission/alarm-ring', maxRingDurationSeconds: 0 },
});
```

Route from whichever native record exists on launch and on resume:

```ts
const handoff = await ExpoAlarm.getPendingNativeAlarmHandoffAsync();
const context = handoff ? null : await ExpoAlarm.getCurrentAlarmContextAsync();
const alarmId = handoff?.alarmId ?? context?.id;

if (alarmId) {
  router.replace(`/mission/${alarmId}`);
  await ExpoAlarm.clearPendingNativeAlarmHandoffAsync();
}
```

Then stop the alarm only once the user actually finishes:

```ts
await ExpoAlarm.completeNativeAlarmAsync(alarmId);
await ExpoAlarm.cancelAlarmAsync(alarmId); // then reschedule if the alarm repeats
```

Events (`onAlarmTriggered`, `onAlarmAction`, `onAlarmStateChange`) fire only when a JS runtime is
alive. Everything they carry is also persisted natively, so reconcile from the async getters on every
launch and foreground. See the [API reference](https://react-native-alarm-scheduler.vercel.app/api/events).

## Platform support

| Capability | Android | iOS | Web |
| --- | :---: | :---: | :---: |
| Schedule, list and cancel app-owned alarms | ✅ | ✅ | ❌ |
| Permissions and settings surfaces | ✅ | ✅ | ❌ |
| Custom alarm sound | ✅ | ✅ | ❌ |
| Ring until the app says stop (`openMissionOnly`) | ✅ | ⚠️ | ❌ |
| Cold-launch handoff, action records, backup alarms | ✅ | ✅ | ❌ |
| Survive reboot | ✅ | ✅ | ❌ |
| Create an alarm in the system Clock app | ✅ | ❌ | ❌ |
| Open the system alarm app | ✅ | ❌ | ❌ |

⚠️ On iOS the ringing surface belongs to AlarmKit, so the system may still expose a stop control the
package cannot remove; `stopIntentBehavior: 'rescheduleImmediate'` re-arms behind it. On Android the
package owns the ringing surface outright, so `openMissionOnly` genuinely has no exit.

Web is supported only as explicit unavailable/no-op behavior.

## Contributing

```sh
npm install
npm run build
npm run lint
```

Run the example app with `cd example && npm install && npm run android`.

## License

MIT
