import { NativeModule, requireNativeModule } from "expo";

import type {
  AlarmPermissionResponse,
  AlarmAction,
  AlarmContext,
  AlarmOccurrence,
  AlarmOccurrenceResolution,
  AlarmOccurrenceResolutionResult,
  AlarmScheduleInput,
  AlarmSchedulerModuleEvents,
  NativeAlarmBackupResult,
  NativeAlarmDebugState,
  ScheduledAlarm,
} from "./AlarmScheduler.types";

declare class AlarmSchedulerModule extends NativeModule<AlarmSchedulerModuleEvents> {
  getPermissionsAsync(): Promise<AlarmPermissionResponse>;
  requestPermissionsAsync(): Promise<AlarmPermissionResponse>;
  openAlarmSettingsAsync(): Promise<boolean>;
  openFullScreenIntentSettingsAsync(): Promise<boolean>;
  scheduleAlarmAsync(alarm: AlarmScheduleInput): Promise<ScheduledAlarm>;
  cancelAlarmAsync(id: string): Promise<boolean>;
  getScheduledAlarmsAsync(): Promise<ScheduledAlarm[]>;
  getCurrentAlarmContextAsync(): Promise<AlarmContext | null>;
  getPendingAlarmActionsAsync(): Promise<AlarmAction[]>;
  clearPendingAlarmActionsAsync(ids?: string[]): Promise<void>;
  getPendingNativeAlarmHandoffAsync(): Promise<AlarmAction | null>;
  clearPendingNativeAlarmHandoffAsync(): Promise<void>;
  completeNativeAlarmAsync(alarmId: string): Promise<void>;
  resolveAlarmOccurrenceAsync(
    occurrenceId: string,
    resolution: AlarmOccurrenceResolution,
  ): Promise<AlarmOccurrenceResolutionResult>;
  getAlarmOccurrencesAsync(alarmId?: string): Promise<AlarmOccurrence[]>;
  cancelAlarmOccurrenceAsync(occurrenceId: string): Promise<boolean>;
  scheduleNativeAlarmBackupAsync(
    alarmId: string,
    delaySeconds?: number,
  ): Promise<NativeAlarmBackupResult>;
  cancelNativeAlarmBackupAsync(alarmId: string): Promise<boolean>;
  clearBypassAsync(alarmId: string): Promise<void>;
  resetNativeAlarmCompletionAsync(alarmId: string): Promise<void>;
  getNativeAlarmDebugStateAsync(
    alarmId: string,
  ): Promise<NativeAlarmDebugState>;
  setSystemAlarmAsync(alarm: AlarmScheduleInput): Promise<boolean>;
  openSystemAlarmAppAsync(): Promise<boolean>;
}

export const AlarmScheduler =
  requireNativeModule<AlarmSchedulerModule>("AlarmScheduler");

export default AlarmScheduler;
