# Changelog

## Unreleased

### 🛠 Breaking changes

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
