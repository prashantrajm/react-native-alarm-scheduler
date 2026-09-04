import { useEffect } from "react";
import { AppState, Linking } from "react-native";
import AlarmScheduler from "react-native-alarm-scheduler";

import { toErrorMessage } from "./format";
import type { LogEntry } from "./types";

type AppendLog = (
  title: string,
  detail?: unknown,
  level?: LogEntry["level"]
) => void;

function alarmIdFromUrl(url: string) {
  const match = url.match(/\/alarm\/([^/?#]+)/);
  return match ? decodeURIComponent(match[1]) : undefined;
}

export function useAlarmLifecycle(options: {
  appendLog: AppendLog;
  refresh: (alarmId?: string) => Promise<void>;
  showAlarm: (alarmId?: string) => void;
}) {
  const { appendLog, refresh, showAlarm } = options;
  useEffect(() => {
    const onTriggered = AlarmScheduler.addListener(
      "onAlarmTriggered",
      (event) => {
        appendLog("Alarm triggered", event);
        showAlarm(event.id);
        void refresh(event.id);
      }
    );
    const onAction = AlarmScheduler.addListener("onAlarmAction", (event) => {
      appendLog(`Native action: ${event.action}`, event);
      showAlarm(event.alarmId);
      void refresh(event.alarmId);
    });
    const onState = AlarmScheduler.addListener(
      "onAlarmStateChange",
      (event) => {
        appendLog(`State changed: ${event.state}`, event);
        void refresh(event.id);
      }
    );
    const appState = AppState.addEventListener("change", (state) => {
      if (state === "active") void refresh();
    });
    const urlListener = Linking.addEventListener("url", ({ url }) => {
      appendLog("App opened from alarm", { url });
      const alarmId = alarmIdFromUrl(url);
      showAlarm(alarmId);
      void refresh(alarmId);
    });

    void Linking.getInitialURL()
      .then((url) => {
        if (url) appendLog("App launched from alarm", { url });
        const alarmId = url ? alarmIdFromUrl(url) : undefined;
        if (alarmId) showAlarm(alarmId);
        return refresh(alarmId);
      })
      .catch((caught) => {
        appendLog("Initial refresh failed", toErrorMessage(caught), "error");
      });

    return () => {
      onTriggered.remove();
      onAction.remove();
      onState.remove();
      appState.remove();
      urlListener.remove();
    };
  }, [appendLog, refresh, showAlarm]);
}
