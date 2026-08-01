# Changelog

## 0.2.1

Documentation only. No runtime, API or native behavior changes.

### 📝 Documentation

- Rewrite the README as a landing page — features, install, usage and the platform capability table —
  instead of a full API reference. The npm package page now shows this rather than the previous
  600-line document.
- Add a documentation site at <https://react-native-alarm-scheduler.vercel.app> covering guides,
  per-platform behavior and the complete API reference.
- Add the MIT `LICENSE` file that `package.json` already declared. It is now included in the
  published tarball.

## 0.2.0

No TypeScript API was removed or changed incompatibly, and iOS behavior is untouched. Android
runtime behavior, however, changes substantially — read this section before upgrading an Android app.

### 🛠 Breaking changes

- **Android alarms now keep ringing.** A fired alarm used to post one notification that played the
  channel sound once and could be swiped away. It now starts a foreground service that loops the
  alarm audio and shows a full-screen ringing screen until the user stops it, the alarm hits
  `android.maxRingDurationSeconds` (default 300), or the app calls `completeNativeAlarmAsync()`.
  Set `android: { fullScreen: false, maxRingDurationSeconds: 5 }` to approximate the old behavior.
- **Android exact-alarm permission now matters more.** Without it the ringing service cannot start
  at all, because Android only exempts exact alarms from the background foreground-service
  restriction. The alarm degrades to a notification. Gate scheduling on `canScheduleExactAlarms`.
- **The package's Android manifest now contributes permissions and components** to the host app:
  `WAKE_LOCK`, `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `USE_FULL_SCREEN_INTENT`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_SPECIAL_USE`, `DISABLE_KEYGUARD`, `TURN_SCREEN_ON`, plus a foreground service,
  a ringing activity and a boot receiver. The `specialUse` foreground service type requires a
  justification in Play Console.
- **Android one-shot alarms stay in `getScheduledAlarmsAsync()` after firing**, until they are
  completed or cancelled, so the completion flow can still resolve them. They used to disappear the
  moment they fired. This matches existing iOS behavior.
- **Android alarms now survive reboots.** Previously they were silently lost; an app that
  rescheduled everything on launch to work around that will now schedule over an already-armed
  alarm. This is harmless — ids are stable and re-arming replaces — but the workaround is redundant.

### 🎉 New features

- Bring Android to feature parity with the iOS AlarmKit flow. Alarms now ring through a foreground
  service with a full-screen lock-screen UI, looping alarm-stream audio, volume pinning, and
  completion gating — the Android module no longer stubs the handoff, action, context, completion or
  backup APIs.
- Add `android` options to `scheduleAlarmAsync()` covering metadata, presentation, sound, vibration,
  volume enforcement, full-screen behavior, deep-link hand-off, ring duration and backup delay. Every
  field that means the same thing on both platforms falls back to the matching `ios` option, so
  existing AlarmKit-shaped call sites behave identically on Android with no changes.
- Restore Android alarms across reboots, app updates, and time/timezone changes.
- Add `openFullScreenIntentSettingsAsync()` plus `canUseFullScreenIntent` and `canPostNotifications`
  on `AlarmPermissionResponse` for the Android 14+ full-screen intent grant.
- Add an `addUseExactAlarmPermission` config plugin option.

### 🐛 Bug fixes

- Android alarms no longer stop at a single, swipe-away notification sound.
- Android `onAlarmTriggered`, `onAlarmAction` and `onAlarmStateChange` are now actually emitted.
- Fall back to `setAndAllowWhileIdle()` when exact alarms are revoked instead of failing to schedule.
- Never let a failed foreground-service start crash the host app. When Android refuses the start —
  revoked exact alarms, an OEM restriction, a restricted standby bucket — the alarm now falls back
  to a full-screen-intent notification that rings through its own channel instead of throwing out of
  the broadcast receiver.
- Record the native handoff and emit `onAlarmTriggered` from the receiver, before the ringing service
  is started, so app routing survives any failure in the presentation layer.

### 💡 Others

- Move the Android alarm store under an `alarm:` preference key prefix, migrating existing records.

## 0.1.7

### 🛠 Breaking changes

### 🎉 New features

- Add a durable iOS native alarm handoff API for AlarmKit intent-driven app launch routing.
- Add iOS AlarmKit intent invocation debug counters to native alarm debug state.

### 🐛 Bug fixes

- Make iOS AlarmKit intent types module-visible and use computed foreground intent modes.
- Force backup AlarmKit timer alerts to include an explicit stop button presentation.

### 💡 Others

- Enable `NSSupportsLiveActivities` from the config plugin for iOS AlarmKit intent support.

## 0.1.6

### 🛠 Breaking changes

### 🎉 New features

- Add iOS AlarmKit `ios.soundName` support for named custom alert sounds.
- Add config plugin `iosAlarmSounds` support for bundling custom iOS alarm sound files.
- Add deterministic iOS AlarmKit backup timer scheduling/canceling APIs for completion-gated native alarm flows.

### 🐛 Bug fixes

- Replace fresh iOS retry alarm UUIDs with a cancel-before-replace deterministic backup id for `rescheduleImmediate`.

### 💡 Others

## 0.1.5

### 🎉 New features

- Add iOS `alertActionMode: 'openMissionOnly'` to prefer AlarmKit's secondary-only alert presentation where supported.
- Expand `getNativeAlarmDebugStateAsync()` with AlarmKit alert/button configuration details.

## 0.1.4

### 🐛 Bug fixes

- Fix iOS `rescheduleImmediate` retry alarms by generating valid UUID retry alarm ids.
- Move iOS retry scheduling far enough ahead to target the next available minute.

## 0.1.3

### 🎉 New features

- Add `openApp` and `rescheduleImmediate` iOS stop intent behaviors.
- Add `completeNativeAlarmAsync()` and `clearBypassAsync()` for completion-gated native stop retry flows.

## 0.1.2

### 🎉 New features

- Add built-in iOS AlarmKit App Intents for native stop and secondary alarm actions.
- Add pending alarm action APIs and best-effort foreground action/state listeners.

## 0.1.1

### 🎉 New features

- Add iOS AlarmKit metadata, presentation options, and `getCurrentAlarmContextAsync()` for app-resolved alarm routing.

## 0.1.0

### 🎉 New features

- Add Android alarm scheduling, Android Clock intents, iOS AlarmKit bridge, TypeScript API, config plugin, and example app wiring.
