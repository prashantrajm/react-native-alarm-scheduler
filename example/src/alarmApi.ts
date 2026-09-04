import AlarmScheduler, {
  type AlarmOccurrence,
} from "react-native-alarm-scheduler";

import type { AlarmSnapshot } from "./types";

export async function readAlarmSnapshot(
  preferredAlarmId?: string,
  selectedAlarmId?: string
): Promise<{ snapshot: AlarmSnapshot; selectedAlarmId?: string }> {
  const [
    permissions,
    scheduled,
    occurrences,
    currentContext,
    pendingHandoff,
    pendingActions,
  ] = await Promise.all([
    AlarmScheduler.getPermissionsAsync(),
    AlarmScheduler.getScheduledAlarmsAsync(),
    AlarmScheduler.getAlarmOccurrencesAsync(),
    AlarmScheduler.getCurrentAlarmContextAsync(),
    AlarmScheduler.getPendingNativeAlarmHandoffAsync(),
    AlarmScheduler.getPendingAlarmActionsAsync(),
  ]);
  const nextAlarmId =
    currentContext?.id ||
    pendingHandoff?.alarmId ||
    preferredAlarmId ||
    selectedAlarmId ||
    scheduled[0]?.id;
  const debug = nextAlarmId
    ? await AlarmScheduler.getNativeAlarmDebugStateAsync(nextAlarmId)
    : null;

  return {
    selectedAlarmId: nextAlarmId,
    snapshot: {
      permissions,
      scheduled,
      occurrences,
      currentContext,
      pendingHandoff,
      pendingActions,
      debug,
    },
  };
}

export async function scheduleExampleAlarm(options: {
  alarmId: string;
  title: string;
  delaySeconds: number;
  soundUri?: string;
  silent: boolean;
  requiresAppCompletion: boolean;
}) {
  const timestamp = Date.now() + options.delaySeconds * 1000;
  const date = new Date(timestamp);
  await AlarmScheduler.requestPermissionsAsync();
  return AlarmScheduler.scheduleAlarmAsync({
    id: options.alarmId,
    hour: date.getHours(),
    minute: date.getMinutes(),
    timestamp,
    title: options.title,
    soundUri: options.soundUri,
    ios: {
      alertTitle: options.title,
      metadata: { source: "example-app" },
      alertActionMode: options.requiresAppCompletion
        ? "openAppOnly"
        : "default",
      stopButtonTitle: "Stop",
      secondaryButtonTitle: "Open alarm",
      stopIntentBehavior: options.requiresAppCompletion
        ? "rescheduleImmediate"
        : "recordOnly",
      secondaryButtonBehavior: "openApp",
      silent: options.silent,
    },
    android: {
      alertBody: "Open the app to manage this alarm",
      launchUri: "alarm-scheduler-example://alarm/{alarmId}",
      maxRingDurationSeconds: options.requiresAppCompletion ? 0 : 180,
      fullScreen: true,
      fullScreenTarget: "native",
      silent: options.silent,
    },
  });
}

export function resolveExampleOccurrence(
  occurrence: AlarmOccurrence,
  kind: "complete" | "defer" | "followUp",
  delaySeconds: number
) {
  return AlarmScheduler.resolveAlarmOccurrenceAsync(
    occurrence.occurrenceId,
    kind === "complete"
      ? {
          outcome: "completed",
          idempotencyKey: `complete:${occurrence.occurrenceId}`,
        }
      : {
          outcome: kind === "defer" ? "deferred" : "completed",
          next: {
            delaySeconds,
            relationship: kind === "defer" ? "deferred" : "followUp",
            metadata: { source: "example-app" },
          },
          idempotencyKey: `${kind}:${occurrence.occurrenceId}`,
        }
  );
}

export function setSystemTestAlarm() {
  const date = new Date(Date.now() + 2 * 60 * 1000);
  return AlarmScheduler.setSystemAlarmAsync({
    hour: date.getHours(),
    minute: date.getMinutes(),
    title: "Alarm Scheduler example",
    showUi: true,
  });
}
