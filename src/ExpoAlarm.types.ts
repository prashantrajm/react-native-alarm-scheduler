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
  /**
   * Android 14+ gates full-screen alarm UI behind a separate user grant. `false` means the
   * alarm still rings but only surfaces as a heads-up notification on a locked device.
   * Always `true` on older Android versions, iOS and web.
   */
  canUseFullScreenIntent?: boolean;
  /** Android 13+ POST_NOTIFICATIONS grant. Always `true` elsewhere. */
  canPostNotifications?: boolean;
};

export type ExpoAlarmModuleEvents = {
  onAlarmTriggered: (alarm: ScheduledAlarm) => void;
  onAlarmAction: (action: AlarmAction) => void;
  onAlarmStateChange: (event: AlarmStateChange) => void;
};

export type AlarmWeekday = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export type AlarmMetadataValue = string | number | boolean;

export type AlarmMetadata = Record<string, AlarmMetadataValue>;

/**
 * Controls which buttons the ringing alert offers.
 *
 * `default` shows a stop button. `openAppOnly` removes it, leaving a single button that opens
 * your app while the alarm keeps ringing; only `completeNativeAlarmAsync()` ends the ring.
 *
 * `openMissionOnly` is the former name of `openAppOnly` and is still accepted.
 *
 * @see https://react-native-alarm-scheduler.vercel.app/guides/completion-gating
 */
export type AlarmAlertActionMode =
  | "default"
  | "openAppOnly"
  /** @deprecated Use `openAppOnly`. Still accepted; will be removed in a future major. */
  | "openMissionOnly";

export type IosAlarmOptions = {
  metadata?: AlarmMetadata;
  alertTitle?: string;
  alertActionMode?: AlarmAlertActionMode;
  stopButtonTitle?: string;
  secondaryButtonTitle?: string;
  countdownTitle?: string;
  stopIntentBehavior?: "recordOnly" | "openApp" | "rescheduleImmediate";
  secondaryButtonBehavior?: "openApp" | "recordOnly" | "none";
  soundName?: string;
};

/**
 * Android-only alarm behaviour.
 *
 * Every field that means the same thing on both platforms falls back to the matching `ios`
 * option when omitted, so an app already written against the AlarmKit flow — `ios.metadata`,
 * `ios.alertActionMode`, `ios.stopIntentBehavior` — behaves identically on Android with no
 * changes. Set fields here only when the two platforms should differ.
 */
export type AndroidAlarmOptions = {
  /** Carried through the alarm and handed back on the fired alarm, actions and context. */
  metadata?: AlarmMetadata;
  alertTitle?: string;
  /** Secondary line on the ringing screen and notification. Defaults to `"Alarm"`. */
  alertBody?: string;
  /**
   * `openAppOnly` removes every way to silence the alarm except handing off to the app,
   * which must then call `completeNativeAlarmAsync()`. `default` also shows a stop button.
   */
  alertActionMode?: AlarmAlertActionMode;
  stopButtonTitle?: string;
  secondaryButtonTitle?: string;
  /** `rescheduleImmediate` re-arms a backup alarm whenever the user stops without completing. */
  stopIntentBehavior?: "recordOnly" | "openApp" | "rescheduleImmediate";
  secondaryButtonBehavior?: "openApp" | "recordOnly" | "none";
  /** Name of a file in `android/app/src/main/res/raw` (extension optional). */
  soundName?: string;
  /** Any content/resource URI. Takes precedence over `soundName`. */
  soundUri?: string;
  /** Defaults to `true`. */
  vibrate?: boolean;
  /**
   * Pins the alarm stream volume for the duration of the ring and restores it afterwards,
   * defeating the volume-down escape hatch. Defaults to `true`.
   */
  enforceVolume?: boolean;
  /** Restore the user's previous alarm volume when the ring ends. Defaults to `true`. */
  restoreVolume?: boolean;
  /** Fraction of max alarm volume to ring at, 0–1. Defaults to `1`. */
  volume?: number;
  /** Take over the screen (lock screen included) when the alarm fires. Defaults to `true`. */
  fullScreen?: boolean;
  /**
   * `native` (default) shows the library's own lock-screen ring UI, which appears instantly and
   * hands off to the app on tap. `app` launches your app's activity directly — only safe if that
   * activity itself sets `showWhenLocked`.
   */
  fullScreenTarget?: "native" | "app";
  /**
   * Deep link opened when the user hands off to the app, e.g. `"myapp://alarm/ring"`.
   * `{alarmId}` is substituted if present, otherwise `?alarmId=` is appended.
   */
  launchUri?: string;
  /** Stop ringing after this many seconds. Defaults to 300. `0` disables the timeout. */
  maxRingDurationSeconds?: number;
  /** Delay used when re-arming a backup alarm. Defaults to 1 second, floor 0.1. */
  backupDelaySeconds?: number;
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
  backupAlarmId?: string;
  backupScheduledFor?: number;
  backupDelaySeconds?: number;
  /** Android: set on the handoff recorded when the alarm itself started ringing. */
  trigger?: boolean;
  /** Android: set on the action recorded when a ring hit `maxRingDurationSeconds`. */
  timedOut?: boolean;
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
  android?: AndroidAlarmOptions;
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
  nativeAlarmId?: string;
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
  pendingHandoff?: AlarmAction | null;
  intentDebugCounts?: Record<string, number>;
  currentContext: AlarmContext | null;
  /** Always reported in canonical form, even when scheduled with the legacy `openMissionOnly`. */
  alertActionMode?: "default" | "openAppOnly";
  stopButtonIncluded?: boolean;
  secondaryButtonIncluded?: boolean;
  secondaryButtonBehavior?: "openApp" | "recordOnly" | "none";
  stopIntentBehavior?: "recordOnly" | "openApp" | "rescheduleImmediate";
  alertInitializer?:
    | "secondaryOnly"
    | "legacyStopButton"
    | "androidRingService";
  runtimeSupportsSecondaryOnlyAlert?: boolean;
  sound?: "default" | "named";
  soundName?: string;
  /** Android: the ring service is currently playing this alarm. */
  isRinging?: boolean;
  /** Android: the alarm is still present in the native store. */
  isScheduled?: boolean;
  canUseFullScreenIntent?: boolean;
  canScheduleExactAlarms?: boolean;
};

export type NativeAlarmBackupResult = {
  alarmId: string;
  backupAlarmId: string;
  scheduled: boolean;
  scheduledFor?: number;
  delaySeconds: number;
};
