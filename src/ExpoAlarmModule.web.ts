import { registerWebModule, NativeModule } from "expo";

import type {
  AlarmPermissionResponse,
  AlarmScheduleInput,
  ExpoAlarmModuleEvents,
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
    throw new Error("expo-alarm is only available on Android and iOS.");
  }

  async cancelAlarmAsync(_id: string): Promise<boolean> {
    return false;
  }

  async getScheduledAlarmsAsync(): Promise<ScheduledAlarm[]> {
    return [];
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
