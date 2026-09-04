# react-native-alarm-scheduler

[![npm version](https://img.shields.io/npm/v/react-native-alarm-scheduler.svg)](https://www.npmjs.com/package/react-native-alarm-scheduler)
[![license](https://img.shields.io/npm/l/react-native-alarm-scheduler.svg)](https://github.com/prashantrajm/react-native-alarm-scheduler/blob/main/LICENSE)
![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios-lightgrey)

Real, user-visible alarms for React Native and Expo — AlarmKit on iOS, an equivalent on Android.

iOS 26 shipped AlarmKit: an alarm that rings on the lock screen, through silent mode and Focus,
whether or not your app is running. Android ships no such framework. This package gives you AlarmKit
on iOS and builds the equivalent on Android out of `AlarmManager.setAlarmClock`, a foreground service
that keeps ringing through Doze and a killed app, and a full-screen lock-screen ring UI — behind one
typed API.

Notification libraries schedule a notification and hope the device is awake to show it. This
schedules an actual alarm.

## Features

- ⏰ **App-owned native alarms** on Android and iOS from one typed API.
- 🔒 **Ring until your app says stop** — with `openAppOnly`, only `completeNativeAlarmAsync()` ends it.
- 📢 **Stays audible on Android** — loops on the alarm stream, ignoring the ringer and Do Not Disturb, and re-raises the volume when anything lowers it.
- 📱 **Full-screen lock-screen ringing UI** backed by a foreground service, so a killed app still rings.
- 🔁 **Survives reboots**, app updates, and clock/timezone changes.
- 🧭 **Cold-launch handoff records** written natively before any JS runs, so your app always knows why it opened.
- 🎵 **User-selected alarm sounds** — pass a picker URI at runtime; each alarm can use a different local audio file.
- 🔇 **Silent alarms** — suppress audio while preserving native alarm presentation and optional vibration.
- 🕐 **System Clock integration** on Android via `ACTION_SET_ALARM` and `ACTION_SHOW_ALARMS`.
- 🧩 **Expo config plugin** for permissions and `NSAlarmKitUsageDescription`.
- 🔷 **Fully typed** TypeScript API, with explicit unavailable behavior where the OS cannot schedule alarms.

## Documentation

📖 **[Documentation](https://react-native-alarm-scheduler.vercel.app)** — guides for scheduling, handoffs, and sounds.

- **[API reference](https://react-native-alarm-scheduler.vercel.app/api)** — every method, type, and event.
- **[Platform behavior](https://react-native-alarm-scheduler.vercel.app/platforms/android)** — Android ringing internals and iOS AlarmKit limits.
- **[Example app](https://github.com/prashantrajm/react-native-alarm-scheduler/tree/main/example)** — a runnable Expo app exercising the full API.
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
import AlarmScheduler from 'react-native-alarm-scheduler';

const permissions = await AlarmScheduler.requestPermissionsAsync();

if (permissions.canScheduleExactAlarms) {
  const alarm = await AlarmScheduler.scheduleAlarmAsync({
    hour: 7,
    minute: 30,
    title: 'Morning alarm',
    weekdays: [1, 2, 3, 4, 5], // ISO: 1 = Monday, 7 = Sunday
  });

  await AlarmScheduler.cancelAlarmAsync(alarm.id);
}
```

List and cancel what you scheduled:

```ts
const alarms = await AlarmScheduler.getScheduledAlarmsAsync();

for (const alarm of alarms) {
  await AlarmScheduler.cancelAlarmAsync(alarm.id);
}
```

### Routing when an alarm opens your app

Events (`onAlarmTriggered`, `onAlarmAction`, `onAlarmStateChange`) fire only when a JS runtime is
alive — which it is not on a cold launch from the lock screen. Everything they carry is also written
natively before any JS runs, so reconcile from the async getters on every launch and foreground:

```ts
const handoff = await AlarmScheduler.getPendingNativeAlarmHandoffAsync();
const context = handoff ? null : await AlarmScheduler.getCurrentAlarmContextAsync();
const alarmId = handoff?.alarmId ?? context?.id;

if (alarmId) {
  router.replace(`/alarm/${alarmId}`);
  await AlarmScheduler.clearPendingNativeAlarmHandoffAsync();
}
```

See the [API reference](https://react-native-alarm-scheduler.vercel.app/api/events).

### Ringing until your app says stop

Set `alertActionMode: 'openAppOnly'` and the ringing alert loses its stop button — the only way out
opens your app, and the alarm keeps ringing until you call `completeNativeAlarmAsync(alarmId)`.
Useful when "the user pressed stop" is not proof of anything:

```ts
await AlarmScheduler.scheduleAlarmAsync({
  hour: 7,
  minute: 0,
  title: 'Wake up',
  // Android inherits every shared iOS field; set android only where platforms differ.
  ios: { alertActionMode: 'openAppOnly', stopIntentBehavior: 'rescheduleImmediate' },
  android: { maxRingDurationSeconds: 0 },
});
```

The guarantee is absolute on Android and best-effort on iOS — see
[Completion gating](https://react-native-alarm-scheduler.vercel.app/guides/completion-gating).

## Platform support

| Capability | Android | iOS |
| --- | :---: | :---: |
| Schedule, list and cancel app-owned alarms | ✅ | ✅ |
| Permissions and settings surfaces | ✅ | ✅ |
| Custom alarm sound | ✅ | ✅ physical device; system default in Simulator |
| Silent alarm | ✅ | ✅ physical device; rejected in Simulator |
| Ring until the app says stop (`openAppOnly`) | ✅ | ⚠️ |
| Cold-launch handoff, action records, backup alarms | ✅ | ✅ |
| Deferred and follow-up alarm occurrences | ✅ | ✅ |
| Survive reboot | ✅ | ✅ |
| Create an alarm in the system Clock app | ✅ | ❌ |
| Open the system alarm app | ✅ | ❌ |

⚠️ Android lets the app own the ringing surface, so `openAppOnly` removes the stop control outright.
On iOS the surface belongs to AlarmKit, which may still expose a system stop affordance the package
cannot remove; `stopIntentBehavior: 'rescheduleImmediate'` re-arms behind it.

On web, `scheduleAlarmAsync` and `setSystemAlarmAsync` throw; every other method resolves to an
explicit unavailable or no-op result, so a universal app still compiles and runs.

## Deferred and follow-up occurrences

Resolve a ringing occurrence and create its next delivery without re-registering the alarm
definition in application code:

```ts
await AlarmScheduler.resolveAlarmOccurrenceAsync(occurrenceId, {
  outcome: 'deferred',
  next: {
    delaySeconds: 5 * 60,
    relationship: 'deferred',
  },
  idempotencyKey: `defer:${occurrenceId}:1`,
});
```

Use `relationship: 'followUp'` with `outcome: 'completed'` to schedule another delivery after the
current occurrence is complete. Repeating primaries receive a fresh `occurrenceId` for every
delivery, and idempotency keys are scoped to that concrete occurrence. Resolving a delivery leaves
the repeating definition and its next scheduled delivery intact. See
[Alarm occurrences](https://react-native-alarm-scheduler.vercel.app/api/occurrences).

## Contributing

```sh
npm install
npm run build
npm run lint
```

Run the example app with `cd example && npm install && npm run android`.

## License

MIT
