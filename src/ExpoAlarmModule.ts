import { NativeModule, requireNativeModule } from "expo";

import type {
  AlarmPermissionResponse,
  AlarmAction,
  AlarmContext,
  AlarmScheduleInput,
  ExpoAlarmModuleEvents,
  ScheduledAlarm,
} from "./ExpoAlarm.types";

declare class ExpoAlarmModule extends NativeModule<ExpoAlarmModuleEvents> {
  getPermissionsAsync(): Promise<AlarmPermissionResponse>;
  requestPermissionsAsync(): Promise<AlarmPermissionResponse>;
  openAlarmSettingsAsync(): Promise<boolean>;
  scheduleAlarmAsync(alarm: AlarmScheduleInput): Promise<ScheduledAlarm>;
  cancelAlarmAsync(id: string): Promise<boolean>;
  getScheduledAlarmsAsync(): Promise<ScheduledAlarm[]>;
  getCurrentAlarmContextAsync(): Promise<AlarmContext | null>;
  getPendingAlarmActionsAsync(): Promise<AlarmAction[]>;
  clearPendingAlarmActionsAsync(ids?: string[]): Promise<void>;
  completeNativeAlarmAsync(alarmId: string): Promise<void>;
  clearBypassAsync(alarmId: string): Promise<void>;
  setSystemAlarmAsync(alarm: AlarmScheduleInput): Promise<boolean>;
  openSystemAlarmAppAsync(): Promise<boolean>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoAlarmModule>("ExpoAlarm");
