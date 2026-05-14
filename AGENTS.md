# Agent Notes

## Project

`react-native-alarm-scheduler` is a published React Native/Expo native module for user-visible alarms.

- JS entry: `src/index.ts`
- Android module: `android/src/main/java/expo/modules/alarm/`
- iOS module: `ios/ExpoAlarmModule.swift`
- Config plugin: `app.plugin.js`
- Example app: `example/`

The public npm package name is `react-native-alarm-scheduler`; the native module name remains `ExpoAlarm`.

## Native Boundaries

- Android supports app-owned alarms through `AlarmManager.setAlarmClock`.
- Android system Clock integration uses `AlarmClock.ACTION_SET_ALARM` and `AlarmClock.ACTION_SHOW_ALARMS`.
- iOS scheduling uses AlarmKit only on iOS 26+ with an iOS 26 SDK build.
- iOS cannot create alarms in the system Clock app through public APIs.
- Web is unsupported except for explicit unavailable/no-op behavior.

Keep the README capability table honest when changing native behavior.

## Verification

Run before pushing meaningful changes:

```sh
npm run build
npm run lint
npm pack --dry-run
```

For native changes, also run:

```sh
cd example/android
./gradlew :app:assembleDebug
```

iOS validation:

```sh
xcodebuild -quiet -workspace example/ios/mymoduleexample.xcworkspace -scheme mymoduleexample -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" build
```

## Release Notes

- Package metadata must point to `https://github.com/rajmaurya-dev/react-native-alarm-scheduler`.
- After publishing a new version, verify with `npm view react-native-alarm-scheduler version`.
