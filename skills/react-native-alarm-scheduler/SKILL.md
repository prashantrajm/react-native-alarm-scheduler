---
name: react-native-alarm-scheduler
description: Use when adding, debugging or reviewing native alarms in a React Native or Expo app with the react-native-alarm-scheduler package — scheduling alarms, alarm permissions, alarms that ring on a locked screen, alarms that keep ringing until the app confirms completion, AlarmKit on iOS, or AlarmManager/foreground-service ringing on Android. Also use when an alarm does not fire, does not ring, or is silenced too easily.
---

# react-native-alarm-scheduler

Schedules real, user-visible native alarms: AlarmKit on iOS 26+, and the equivalent on Android built
from `AlarmManager.setAlarmClock` plus a foreground ringing service. This is not a notification
scheduler — the alarm rings through Doze, a locked screen, and a killed app.

Full docs: <https://react-native-alarm-scheduler.vercel.app/llms.txt>

## Before writing any code

1. **Confirm the app can run native modules.** This package does not work in Expo Go. The app needs
   a development build or a prebuilt native app. If the user is on Expo Go, say so before anything else.
2. **Confirm the config plugin is registered** in `app.json` / `app.config.js`. Without it the
   Android permissions and `NSAlarmKitUsageDescription` are missing and scheduling fails at runtime,
   not at build time.

```json
{ "expo": { "plugins": [["react-native-alarm-scheduler", { "alarmKitUsageDescription": "…" }]] } }
```

## The six rules that cause most bugs

**1. Gate every schedule on `canScheduleExactAlarms`.** On Android this is not a nicety: without the
exact-alarm grant the ringing foreground service cannot legally start, so the alarm degrades to a
notification. Never call `scheduleAlarmAsync` without checking.

```ts
const p = await AlarmScheduler.requestPermissionsAsync();
if (!p.canScheduleExactAlarms) return; // route the user to settings, explain why
```

**2. Never rely on events.** `onAlarmTriggered`, `onAlarmAction` and `onAlarmStateChange` only fire
when a JS runtime is alive — which is usually false for a 7am alarm. Everything is also persisted
natively. Reconcile on **every launch and every foreground**:

```ts
const handoff = await AlarmScheduler.getPendingNativeAlarmHandoffAsync();
const context = handoff ? null : await AlarmScheduler.getCurrentAlarmContextAsync();
const alarmId = handoff?.alarmId ?? context?.id;
if (alarmId) {
  router.replace(`/alarm/${alarmId}`);
  await AlarmScheduler.clearPendingNativeAlarmHandoffAsync();
}
```

Writing alarm routing *only* inside an event listener is the single most common mistake.

**3. `id` must be a UUID string on iOS.** Android accepts anything. Generate UUIDs so both platforms
can share ids.

**4. Android inherits the `ios` options.** `metadata`, `alertTitle`, `alertActionMode`,
`stopButtonTitle`, `secondaryButtonTitle`, `stopIntentBehavior`, `secondaryButtonBehavior`, `silent`,
`soundUri` and `soundName` fall back to the `ios` value when omitted. Do not duplicate them into
`android` — set `android` fields only where the platforms should genuinely differ (`launchUri`,
`maxRingDurationSeconds`, volume behavior).

**5. `completeNativeAlarmAsync(alarmId)` is mandatory, not advisory.** With
`alertActionMode: 'openAppOnly'` the Android alarm keeps playing until this call lands. Call it
only after the user actually satisfies the completion condition, then `cancelAlarmAsync` and
reschedule if the alarm repeats.

**6. Runtime sounds must be readable local files.** Pass a picker result as the top-level
`soundUri`; the module copies it into durable native storage during `scheduleAlarmAsync`. On iOS it
transcodes the first 29 seconds to a PCM CAF for AlarmKit. DRM-protected Apple Music or Spotify
tracks cannot be imported because the app never receives their audio bytes. iOS Simulator uses the
system default sound because its ToneLibrary can crash SpringBoard for external AlarmKit sounds;
verify custom iOS playback on a physical device.

**7. Use `silent`, not a zero-volume workaround.** `silent: true` overrides `soundUri` and
`soundName`. Android skips playback and volume enforcement while leaving `vibrate` independent. On
physical iOS 26+ devices the config plugin's bundled silent CAF preserves the AlarmKit presentation;
the Simulator rejects silent scheduling, and a missing bundled asset fails scheduling rather than
falling back to the audible system sound.

## Deferred and follow-up occurrences

Use `resolveAlarmOccurrenceAsync` when an active alarm should stop and optionally produce another
delivery. Do not reproduce the native stop, completion reset, definition restoration, and timer
ordering in application code.

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

Use the returned `occurrenceId` with `cancelAlarmOccurrenceAsync`; do not cancel every backup for the
alarm when only one occurrence should be removed. Reconcile persisted state with
`getAlarmOccurrencesAsync()` after cold launch.

Each repeating primary delivery has a new `occurrenceId` while `alarmId` remains stable. Build
idempotency keys from the concrete occurrence, and never cache a primary occurrence id across
deliveries. Resolving the current primary preserves the repeating native schedule.

## Completion-gated alarms

An alarm that keeps ringing until the app confirms the user finished something. Use
`alertActionMode: 'openAppOnly'` to remove the native stop action.

```ts
await AlarmScheduler.scheduleAlarmAsync({
  id: uuid,
  hour: 7,
  minute: 0,
  ios: {
    alertActionMode: 'openAppOnly',
    secondaryButtonTitle: 'Open app',
    stopIntentBehavior: 'rescheduleImmediate',
  },
  android: { launchUri: 'myapp://alarm', maxRingDurationSeconds: 0 },
});
```

Be honest about the guarantee, it differs per platform:

- **Android — absolute.** The package owns the ringing surface. No stop button, back gestures
  swallowed, notification ongoing.
- **iOS — best effort.** AlarmKit owns the surface and may still show a system stop control.
  `stopIntentBehavior: 'rescheduleImmediate'` re-arms a deterministic backup timer behind it. Verify
  what the runtime gave you with `getNativeAlarmDebugStateAsync(alarmId)`: if `alertActionMode` is
  `openAppOnly` but `alertInitializer` is `legacyStopButton`, the stop control cannot be removed.

Never promise a user that an iOS alarm is undismissable.

## Debugging checklist

| Symptom | Check |
| --- | --- |
| Alarm never fires | `canScheduleExactAlarms`; OEM battery optimization (Xiaomi, Oppo, Vivo, Samsung, Huawei) |
| Fires but no full-screen UI on Android 14+ | `canUseFullScreenIntent`, then `openFullScreenIntentSettingsAsync()` |
| Rings but app opens on the wrong screen | Routing lives in an event listener instead of the launch reconcile |
| Alarm stops when the user hits volume down | `android.enforceVolume` was disabled |
| iOS shows a stop button despite `openAppOnly` | `getNativeAlarmDebugStateAsync().alertInitializer` — the runtime forced the legacy presentation |
| Ring stops after 5 minutes | `android.maxRingDurationSeconds` defaults to 300; set `0` |
| Nothing works in Expo Go | Expected. Native module — use a development build |

`getNativeAlarmDebugStateAsync(alarmId)` is the first tool to reach for on Android: it reports
`isRinging`, `isScheduled`, and both permission grants live.

## Do not

- Do not use this for background work that the user should not see. It is a user-visible alarm API.
- Do not try to create alarms in the iOS Clock app — `setSystemAlarmAsync` throws on iOS. There is no
  public API. `AlarmClock.ACTION_SET_ALARM` is Android-only.
- Do not target web. It is explicitly unavailable/no-op.
