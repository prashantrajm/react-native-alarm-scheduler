import type {
  AlarmOccurrence,
  ScheduledAlarm,
} from "react-native-alarm-scheduler";

export function createAlarmId() {
  const segment = () =>
    Math.floor(Math.random() * 0xffff)
      .toString(16)
      .padStart(4, "0");
  return `${segment()}${segment()}-${segment()}-4${segment().slice(
    1
  )}-8${segment().slice(1)}-${segment()}${segment()}${segment()}`;
}

export function formatTime(timestamp: number) {
  return new Date(timestamp).toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function formatDateTime(timestamp: number) {
  return new Date(timestamp).toLocaleString([], {
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

export function formatAlarmSchedule(alarm: ScheduledAlarm) {
  if (alarm.weekdays.length > 0) {
    return `${formatTime(alarm.timestamp)} · repeats`;
  }
  return formatDateTime(alarm.timestamp);
}

export function occurrenceLabel(occurrence: AlarmOccurrence) {
  if (occurrence.relationship === "primary") return "Primary";
  if (occurrence.relationship === "deferred") return "Deferred";
  return "Follow-up";
}

export function toErrorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}
