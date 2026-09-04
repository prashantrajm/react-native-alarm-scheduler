import type {
  AlarmAction,
  AlarmContext,
  AlarmOccurrence,
  AlarmPermissionResponse,
  NativeAlarmDebugState,
  ScheduledAlarm,
} from "react-native-alarm-scheduler";

export type AppTab = "alarms" | "occurrences" | "logs";

export type LogEntry = {
  id: string;
  timestamp: number;
  title: string;
  detail?: unknown;
  level: "info" | "success" | "error";
};

export type AlarmSnapshot = {
  permissions?: AlarmPermissionResponse;
  scheduled: ScheduledAlarm[];
  occurrences: AlarmOccurrence[];
  currentContext: AlarmContext | null;
  pendingHandoff: AlarmAction | null;
  pendingActions: AlarmAction[];
  debug: NativeAlarmDebugState | null;
};
