import { StyleSheet, Text, View } from "react-native";
import type { ScheduledAlarm } from "react-native-alarm-scheduler";

import { formatAlarmSchedule, formatTime } from "../format";
import { colors } from "../theme";
import { AppButton, Badge, Card } from "./Primitives";

export function AlarmCard(props: {
  alarm: ScheduledAlarm;
  busy: boolean;
  onCancel: () => void;
  onInspect: () => void;
}) {
  return (
    <Card>
      <View style={styles.row}>
        <View style={styles.details}>
          <Text style={styles.time}>{formatTime(props.alarm.timestamp)}</Text>
          <Text style={styles.title}>{props.alarm.title}</Text>
          <Text style={styles.schedule}>
            {formatAlarmSchedule(props.alarm)}
          </Text>
        </View>
        <Badge
          tone={props.alarm.relationship === "primary" ? "primary" : "warning"}
        >
          {props.alarm.relationship ?? "primary"}
        </Badge>
      </View>
      <Text numberOfLines={1} style={styles.id}>
        {props.alarm.id}
      </Text>
      <View style={styles.actions}>
        <AppButton
          compact
          disabled={props.busy}
          onPress={props.onInspect}
          title="Inspect"
          tone="neutral"
        />
        <AppButton
          compact
          disabled={props.busy}
          onPress={props.onCancel}
          title="Cancel"
          tone="danger"
        />
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  row: {
    alignItems: "flex-start",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  details: { flex: 1 },
  time: {
    color: colors.text,
    fontSize: 34,
    fontWeight: "800",
    letterSpacing: -0.8,
  },
  title: { color: colors.text, fontSize: 16, fontWeight: "700" },
  schedule: { color: colors.textMuted, fontSize: 13, marginTop: 3 },
  id: { color: colors.textMuted, fontFamily: "monospace", fontSize: 10 },
  actions: { flexDirection: "row", justifyContent: "flex-end" },
});
