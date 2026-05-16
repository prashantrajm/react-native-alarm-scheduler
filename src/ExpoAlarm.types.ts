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
  onAlarmAction: (action: AlarmAction) => void;
  onAlarmStateChange: (event: AlarmStateChange) => void;
};

export type AlarmWeekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export type AlarmMetadataValue = string | number | boolean;

export type AlarmMetadata = Record<string, AlarmMetadataValue>;

export type IosAlarmOptions = {
  metadata?: AlarmMetadata;
  alertTitle?: string;
  alertActionMode?: "default" | "openMissionOnly";
  stopButtonTitle?: string;
  secondaryButtonTitle?: string;
  countdownTitle?: string;
  stopIntentBehavior?: "recordOnly" | "openApp" | "rescheduleImmediate";
  secondaryButtonBehavior?: "openApp" | "recordOnly" | "none";
};

export type AlarmActionType =
  | "nativeStop"
  | "secondaryOpen"
  | "snooze"
  | "dismiss";

export type AlarmAction = {
  id: string;
  alarmId: string;
  action: AlarmActionType;
  timestamp: number;
  foregroundRequested?: boolean;
  rescheduled?: boolean;
  rescheduledAlarmId?: string;
  retryScheduledFor?: number;
};

export type AlarmScheduleInput = {
  id?: string;
  hour: number;
  minute: number;
  title?: string;
  weekdays?: AlarmWeekday[];
  timestamp?: number;
  showUi?: boolean;
  ios?: IosAlarmOptions;
};

export type ScheduledAlarm = {
  id: string;
  hour: number;
  minute: number;
  title: string;
  weekdays: AlarmWeekday[];
  timestamp: number;
  platform: "android" | "ios";
  metadata?: AlarmMetadata;
};

export type AlarmContextState =
  | "scheduled"
  | "alerting"
  | "countdown"
  | "paused";

export type AlarmContext = {
  id: string;
  metadata?: AlarmMetadata;
  state?: AlarmContextState;
};

export type AlarmStateChange = {
  id: string;
  state: AlarmContextState;
  timestamp: number;
  metadata?: AlarmMetadata;
};

export type NativeAlarmDebugState = {
  alarmId: string;
  isComplete: boolean;
  activeRetryAlarmIds: string[];
  pendingActions: AlarmAction[];
  currentContext: AlarmContext | null;
  alertActionMode?: "default" | "openMissionOnly";
  stopButtonIncluded?: boolean;
  secondaryButtonIncluded?: boolean;
  secondaryButtonBehavior?: "openApp" | "recordOnly" | "none";
  stopIntentBehavior?: "recordOnly" | "openApp" | "rescheduleImmediate";
  alertInitializer?: "secondaryOnly" | "legacyStopButton";
  runtimeSupportsSecondaryOnlyAlert?: boolean;
};
