import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import * as DocumentPicker from "expo-document-picker";
import { Platform } from "react-native";
import AlarmScheduler, {
  type AlarmOccurrence,
  type ScheduledAlarm,
} from "react-native-alarm-scheduler";

import { createAlarmId, toErrorMessage } from "./format";
import {
  readAlarmSnapshot,
  resolveExampleOccurrence,
  scheduleExampleAlarm,
  setSystemTestAlarm,
} from "./alarmApi";
import type { AlarmSnapshot, AppTab, LogEntry } from "./types";
import { useAlarmLifecycle } from "./useAlarmLifecycle";

const initialSnapshot: AlarmSnapshot = {
  scheduled: [],
  occurrences: [],
  currentContext: null,
  pendingHandoff: null,
  pendingActions: [],
  debug: null,
};

export function useAlarmController() {
  const [tab, setTab] = useState<AppTab>("alarms");
  const [snapshot, setSnapshot] = useState<AlarmSnapshot>(initialSnapshot);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [title, setTitle] = useState("Morning alarm");
  const [delaySeconds, setDelaySeconds] = useState(60);
  const [relatedDelaySeconds, setRelatedDelaySeconds] = useState(60);
  const [requiresAppCompletion, setRequiresAppCompletion] = useState(true);
  const [sound, setSound] = useState<{ name: string; uri: string }>();
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const [selectedAlarmId, setSelectedAlarmId] = useState<string>();
  const selectedAlarmIdRef = useRef<string | undefined>(undefined);

  useEffect(() => {
    selectedAlarmIdRef.current = selectedAlarmId;
  }, [selectedAlarmId]);

  const appendLog = useCallback(
    (
      titleText: string,
      detail?: unknown,
      level: LogEntry["level"] = "info"
    ) => {
      setLogs((current) =>
        [
          {
            id: `${Date.now()}-${Math.random()}`,
            timestamp: Date.now(),
            title: titleText,
            detail,
            level,
          },
          ...current,
        ].slice(0, 100)
      );
    },
    []
  );

  const refresh = useCallback(async (preferredAlarmId?: string) => {
    const result = await readAlarmSnapshot(
      preferredAlarmId,
      selectedAlarmIdRef.current
    );
    if (result.selectedAlarmId) setSelectedAlarmId(result.selectedAlarmId);
    setSnapshot(result.snapshot);
  }, []);

  const runAction = useCallback(
    async (
      label: string,
      action: () => Promise<unknown>,
      preferredAlarmId?: string
    ) => {
      setBusy(label);
      setError(undefined);
      try {
        const result = await action();
        appendLog(label, result, "success");
        await refresh(preferredAlarmId);
      } catch (caught) {
        const message = toErrorMessage(caught);
        setError(message);
        appendLog(`${label} failed`, message, "error");
      } finally {
        setBusy(undefined);
      }
    },
    [appendLog, refresh]
  );

  const showAlarm = useCallback((alarmId?: string) => {
    if (alarmId) setSelectedAlarmId(alarmId);
    setTab("alarms");
  }, []);
  useAlarmLifecycle({ appendLog, refresh, showAlarm });

  const activeOccurrence = useMemo(() => {
    const contextOccurrenceId = snapshot.currentContext?.occurrenceId;
    const exactOccurrence = snapshot.occurrences.find(
      (occurrence) =>
        occurrence.phase === "ringing" ||
        occurrence.occurrenceId === contextOccurrenceId
    );
    if (exactOccurrence) return exactOccurrence;

    if (snapshot.currentContext?.id) {
      return snapshot.occurrences.find(
        (occurrence) => occurrence.alarmId === snapshot.currentContext?.id
      );
    }
    return undefined;
  }, [snapshot.currentContext, snapshot.occurrences]);

  const activeAlarmId =
    snapshot.currentContext?.id ||
    activeOccurrence?.alarmId ||
    snapshot.pendingHandoff?.alarmId;
  const isAlerting =
    snapshot.currentContext?.state === "alerting" ||
    activeOccurrence?.phase === "ringing";

  const requestPermissions = () =>
    runAction("Permissions requested", () =>
      AlarmScheduler.requestPermissionsAsync()
    );

  const scheduleAlarm = () => {
    const alarmId = createAlarmId();
    return runAction(
      "Alarm scheduled",
      () =>
        scheduleExampleAlarm({
          alarmId,
          title: title.trim() || "Alarm",
          delaySeconds,
          soundUri: sound?.uri,
          requiresAppCompletion,
        }),
      alarmId
    );
  };

  const resolveOccurrence = (
    occurrence: AlarmOccurrence,
    kind: "complete" | "defer" | "followUp"
  ) =>
    runAction(
      kind === "complete"
        ? "Alarm completed"
        : kind === "defer"
        ? "Alarm deferred"
        : "Follow-up scheduled",
      () => resolveExampleOccurrence(occurrence, kind, relatedDelaySeconds),
      occurrence.alarmId
    );

  const pickSound = async () => {
    const result = await DocumentPicker.getDocumentAsync({
      type: "audio/*",
      copyToCacheDirectory: true,
    });
    if (!result.canceled) {
      const picked = result.assets[0];
      setSound({ name: picked.name, uri: picked.uri });
      appendLog("Alarm sound selected", { name: picked.name });
    }
  };

  const cancelAlarm = (alarm: ScheduledAlarm) =>
    runAction(
      "Alarm cancelled",
      () => AlarmScheduler.cancelAlarmAsync(alarm.id),
      alarm.id
    );

  const cancelOccurrence = (occurrence: AlarmOccurrence) =>
    runAction(
      "Occurrence cancelled",
      () => AlarmScheduler.cancelAlarmOccurrenceAsync(occurrence.occurrenceId),
      occurrence.alarmId
    );

  const openAlarmSettings = () =>
    runAction("Alarm settings opened", () =>
      AlarmScheduler.openAlarmSettingsAsync()
    );
  const openFullScreenSettings = () =>
    runAction("Full-screen settings opened", () =>
      AlarmScheduler.openFullScreenIntentSettingsAsync()
    );
  const openSystemAlarmApp = () =>
    runAction("System alarm app opened", () =>
      AlarmScheduler.openSystemAlarmAppAsync()
    );
  const setSystemAlarm = () =>
    runAction("System alarm requested", setSystemTestAlarm);

  const clearPendingActions = () =>
    runAction("Pending actions cleared", async () => {
      await AlarmScheduler.clearPendingAlarmActionsAsync();
      return true;
    });
  const clearHandoff = () =>
    runAction("Pending handoff cleared", async () => {
      await AlarmScheduler.clearPendingNativeAlarmHandoffAsync();
      return true;
    });
  const completeNative = () =>
    activeAlarmId
      ? runAction(
          "Native alarm completed",
          async () => {
            await AlarmScheduler.completeNativeAlarmAsync(activeAlarmId);
            return { alarmId: activeAlarmId };
          },
          activeAlarmId
        )
      : Promise.resolve();
  const resetCompletion = () =>
    selectedAlarmId
      ? runAction(
          "Completion state reset",
          async () => {
            await AlarmScheduler.resetNativeAlarmCompletionAsync(
              selectedAlarmId
            );
            return { alarmId: selectedAlarmId };
          },
          selectedAlarmId
        )
      : Promise.resolve();
  const clearBypass = () =>
    selectedAlarmId
      ? runAction(
          "Bypass state cleared",
          async () => {
            await AlarmScheduler.clearBypassAsync(selectedAlarmId);
            return { alarmId: selectedAlarmId };
          },
          selectedAlarmId
        )
      : Promise.resolve();
  const armBackup = () =>
    selectedAlarmId
      ? runAction(
          "Recovery backup armed",
          () =>
            AlarmScheduler.scheduleNativeAlarmBackupAsync(selectedAlarmId, 10),
          selectedAlarmId
        )
      : Promise.resolve();
  const cancelBackup = () =>
    selectedAlarmId
      ? runAction(
          "Recovery backup cancelled",
          () => AlarmScheduler.cancelNativeAlarmBackupAsync(selectedAlarmId),
          selectedAlarmId
        )
      : Promise.resolve();

  return {
    tab,
    setTab,
    snapshot,
    logs,
    clearLogs: () => setLogs([]),
    title,
    setTitle,
    delaySeconds,
    setDelaySeconds,
    relatedDelaySeconds,
    setRelatedDelaySeconds,
    requiresAppCompletion,
    setRequiresAppCompletion,
    sound,
    clearSound: () => setSound(undefined),
    busy,
    error,
    clearError: () => setError(undefined),
    selectedAlarmId,
    setSelectedAlarmId,
    activeOccurrence,
    activeAlarmId,
    isAlerting,
    refresh,
    requestPermissions,
    scheduleAlarm,
    resolveOccurrence,
    pickSound,
    cancelAlarm,
    cancelOccurrence,
    openAlarmSettings,
    openFullScreenSettings,
    openSystemAlarmApp,
    setSystemAlarm,
    clearPendingActions,
    clearHandoff,
    completeNative,
    resetCompletion,
    clearBypass,
    armBackup,
    cancelBackup,
    platform: Platform.OS,
  };
}

export type AlarmController = ReturnType<typeof useAlarmController>;
