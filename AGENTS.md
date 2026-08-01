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

The docs site is Fumadocs on Astro, in `website/`, deployed to
<https://react-native-alarm-scheduler.vercel.app> on Vercel. It is a separate npm project with its
own lockfile and is excluded from the published package.

- Content: `website/content/docs/**/*.mdx`, ordered by `meta.json` in each folder.
- Sidebar/nav: `website/src/components/docs.tsx`.
- Build: `cd website && npm install && npm run build` (output in `website/dist`).
Vercel settings this build depends on:

- **Root Directory** must be `website`, not the repo root.
- **"Include source files outside of the Root Directory in the Build Step" must be OFF.** With it on,
  Vite walks up from `website/` and parses the repo-root `tsconfig.json`, which extends
  `expo-module-scripts/tsconfig.base`. Vercel only installs `website/`'s dependencies, so that
  package is absent and `astro sync` fails with `Tsconfig not found expo-module-scripts/tsconfig.base`.
  Nothing in `website/` references the parent directory, so excluding it is safe.

To reproduce that failure locally: `mv node_modules/expo-module-scripts /tmp && cd website && npm run build`.

Do not use `<Tabs>` or the `package-install` / `remarkCodeTab` code fences in MDX. Astro renders MDX
content server-side and passes it into the `<Docs>` React island as slot children, so React context
never reaches it and any context-dependent component throws at build time. `Callout`, `Steps` and
`Cards` are context-free and work.

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
