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

## Documentation

The docs site is Fumadocs on Astro, in `website/`. It is a separate npm workspace with its own
lockfile and is excluded from the published package.

- Content: `website/content/docs/**/*.mdx`, ordered by `meta.json` in each folder.
- Sidebar/nav: `website/src/components/docs.tsx`.
- Build: `cd website && npm install && npm run build` (output in `website/dist`).

Do not use `<Tabs>` or the `package-install` / `remarkCodeTab` code fences in MDX. Astro renders MDX
content server-side and passes it into the `<Docs>` React island as slot children, so React context
never reaches it and any context-dependent component throws at build time. `Callout`, `Steps` and
`Cards` are context-free and work.

`docs/` still holds the older hand-written HTML site that `\.github/workflows/pages.yml` deploys to
GitHub Pages. Retire it once the Fumadocs site is deployed.

When native behavior changes, update the affected pages under `website/content/docs/` as well as the
README capability table.

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

- Package metadata must point to `https://github.com/rajmauryafr/react-native-alarm-scheduler`.
- After publishing a new version, verify with `npm view react-native-alarm-scheduler version`.
