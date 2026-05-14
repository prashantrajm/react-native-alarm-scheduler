// Reexport the native module. On web, it will be resolved to ExpoAlarmModule.web.ts
// and on native platforms to ExpoAlarmModule.ts
export { default } from './ExpoAlarmModule';
export { default as ExpoAlarmView } from './ExpoAlarmView';
export * from  './ExpoAlarm.types';
