import { StyleSheet, Text, View } from "react-native";
import type { AlarmOccurrence } from "react-native-alarm-scheduler";

import { formatDateTime, occurrenceLabel } from "../format";
import { colors } from "../theme";
import { AppButton, Badge, Card } from "./Primitives";

export function OccurrenceCard(props: {
  occurrence: AlarmOccurrence;
  busy: boolean;
  onCancel: () => void;
}) {
  const cancellable =
    props.occurrence.phase === "scheduled" ||
    props.occurrence.phase === "ringing";
  const tone =
    props.occurrence.phase === "completed"
      ? "success"
      : props.occurrence.phase === "cancelled"
      ? "neutral"
      : props.occurrence.phase === "ringing"
      ? "danger"
      : "warning";

  return (
    <Card>
      <View style={styles.row}>
        <View style={styles.labels}>
          <Text style={styles.title}>{occurrenceLabel(props.occurrence)}</Text>
          <Text style={styles.time}>
            {formatDateTime(props.occurrence.scheduledFor)}
          </Text>
        </View>
        <Badge tone={tone}>{props.occurrence.phase}</Badge>
      </View>
      <Text numberOfLines={1} style={styles.id}>
        occurrence: {props.occurrence.occurrenceId}
      </Text>
      <Text numberOfLines={1} style={styles.id}>
        alarm: {props.occurrence.alarmId}
      </Text>
      {cancellable ? (
        <AppButton
          compact
          disabled={props.busy}
          onPress={props.onCancel}
          title="Cancel occurrence"
          tone="danger"
        />
      ) : null}
    </Card>
  );
}

const styles = StyleSheet.create({
  row: {
    alignItems: "flex-start",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  labels: { flex: 1 },
  title: { color: colors.text, fontSize: 17, fontWeight: "700" },
  time: { color: colors.textMuted, fontSize: 13, marginTop: 3 },
  id: { color: colors.textMuted, fontFamily: "monospace", fontSize: 10 },
});
