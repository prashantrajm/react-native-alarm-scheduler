export type AlarmAuthorizationStatus =
  | "authorized"
  | "denied"
  | "notDetermined"
  | "unavailable"
  | "unknown";

export type AlarmPermissionResponse = {
  platform: "android" | "ios";
  status: AlarmAuthorizationStatus;
  canScheduleExactAlarms: boolean;
  canOpenSettings: boolean;
};

export type ExpoAlarmModuleEvents = {
  onAlarmTriggered: (alarm: ScheduledAlarm) => void;
};

export type AlarmWeekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export type AlarmScheduleInput = {
  id?: string;
  hour: number;
  minute: number;
  title?: string;
  weekdays?: AlarmWeekday[];
  timestamp?: number;
  showUi?: boolean;
};

export type ScheduledAlarm = {
  id: string;
  hour: number;
  minute: number;
  title: string;
  weekdays: AlarmWeekday[];
  timestamp: number;
  platform: "android" | "ios";
};
