import { registerWebModule, NativeModule } from "expo";

import type {
  AlarmPermissionResponse,
  AlarmAction,
  AlarmContext,
  AlarmScheduleInput,
  ExpoAlarmModuleEvents,
  NativeAlarmBackupResult,
  NativeAlarmDebugState,
  ScheduledAlarm,
} from "./ExpoAlarm.types";

class ExpoAlarmModule extends NativeModule<ExpoAlarmModuleEvents> {
  async getPermissionsAsync(): Promise<AlarmPermissionResponse> {
    return this.unavailablePermission();
  }

  async requestPermissionsAsync(): Promise<AlarmPermissionResponse> {
    return this.unavailablePermission();
  }

  async openAlarmSettingsAsync(): Promise<boolean> {
    return false;
  }

  async scheduleAlarmAsync(
    _alarm: AlarmScheduleInput,
  ): Promise<ScheduledAlarm> {
    throw new Error(
      "react-native-alarm-scheduler is only available on Android and iOS.",
    );
  }

  async cancelAlarmAsync(_id: string): Promise<boolean> {
    return false;
  }

  async getScheduledAlarmsAsync(): Promise<ScheduledAlarm[]> {
    return [];
  }

  async getCurrentAlarmContextAsync(): Promise<AlarmContext | null> {
    return null;
  }

  async getPendingAlarmActionsAsync(): Promise<AlarmAction[]> {
    return [];
  }

  async clearPendingAlarmActionsAsync(_ids?: string[]): Promise<void> {}

  async getPendingNativeAlarmHandoffAsync(): Promise<AlarmAction | null> {
    return null;
  }

  async clearPendingNativeAlarmHandoffAsync(): Promise<void> {}

  async completeNativeAlarmAsync(_alarmId: string): Promise<void> {}

  async scheduleNativeAlarmBackupAsync(
    alarmId: string,
    delaySeconds = 0.1,
  ): Promise<NativeAlarmBackupResult> {
    return {
      alarmId,
      backupAlarmId: "",
      scheduled: false,
      delaySeconds,
    };
  }

  async cancelNativeAlarmBackupAsync(_alarmId: string): Promise<boolean> {
    return false;
  }

  async clearBypassAsync(_alarmId: string): Promise<void> {}

  async resetNativeAlarmCompletionAsync(_alarmId: string): Promise<void> {}

  async getNativeAlarmDebugStateAsync(
    alarmId: string,
  ): Promise<NativeAlarmDebugState> {
    return {
      alarmId,
      isComplete: false,
      activeRetryAlarmIds: [],
      pendingActions: [],
      pendingHandoff: null,
      intentDebugCounts: {},
      currentContext: null,
      alertActionMode: "default",
      stopButtonIncluded: false,
      secondaryButtonIncluded: false,
      secondaryButtonBehavior: "none",
      stopIntentBehavior: "recordOnly",
      alertInitializer: "legacyStopButton",
      runtimeSupportsSecondaryOnlyAlert: false,
      sound: "default",
    };
  }

  async setSystemAlarmAsync(_alarm: AlarmScheduleInput): Promise<boolean> {
    throw new Error("System alarms are only available on Android.");
  }

  async openSystemAlarmAppAsync(): Promise<boolean> {
    return false;
  }

  private unavailablePermission(): AlarmPermissionResponse {
    return {
      platform: "ios",
      status: "unavailable",
      canScheduleExactAlarms: false,
      canOpenSettings: false,
    };
  }
}

export default registerWebModule(ExpoAlarmModule, "ExpoAlarm");
