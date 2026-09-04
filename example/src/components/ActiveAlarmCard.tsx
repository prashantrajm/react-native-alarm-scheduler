import { StyleSheet, Text, View } from "react-native";
import type { AlarmOccurrence } from "react-native-alarm-scheduler";

import { formatTime, occurrenceLabel } from "../format";
import { colors, spacing } from "../theme";
import { AppButton, Badge, Card } from "./Primitives";
import { ChoiceRow } from "./ChoiceRow";

export function ActiveAlarmCard(props: {
  occurrence?: AlarmOccurrence;
  alarmId?: string;
  delaySeconds: number;
  busy: boolean;
  onDelayChange: (seconds: number) => void;
  onComplete: () => void;
  onDefer: () => void;
  onFollowUp: () => void;
  onCompleteNative: () => void;
}) {
  return (
    <Card style={styles.card}>
      <View style={styles.titleRow}>
        <View>
          <Text style={styles.eyebrow}>RINGING NOW</Text>
          <Text style={styles.time}>{formatTime(Date.now())}</Text>
        </View>
        <Badge tone="danger">
          {props.occurrence
            ? occurrenceLabel(props.occurrence)
            : "Native alarm"}
        </Badge>
      </View>
      <Text style={styles.alarmId} numberOfLines={1}>
        {props.alarmId}
      </Text>
      {props.occurrence ? (
        <>
          <Text style={styles.label}>Next occurrence delay</Text>
          <ChoiceRow
            onChange={props.onDelayChange}
            options={[
              { label: "30 sec", value: 30 },
              { label: "1 min", value: 60 },
              { label: "5 min", value: 300 },
            ]}
            value={props.delaySeconds}
          />
          <View style={styles.primaryActions}>
            <AppButton
              disabled={props.busy}
              onPress={props.onDefer}
              title="Snooze"
              tone="neutral"
            />
            <AppButton
              disabled={props.busy}
              onPress={props.onComplete}
              title="Complete"
            />
          </View>
          <AppButton
            disabled={props.busy}
            onPress={props.onFollowUp}
            title="Complete and schedule follow-up"
            tone="ghost"
          />
        </>
      ) : (
        <>
          <Text style={styles.help}>
            Native context is active, but this build did not provide an
            occurrence identity.
          </Text>
          <AppButton
            disabled={props.busy}
            onPress={props.onCompleteNative}
            title="Stop native alarm"
          />
        </>
      )}
    </Card>
  );
}

const styles = StyleSheet.create({
  card: { backgroundColor: colors.dark, borderColor: colors.dark },
  titleRow: {
    alignItems: "flex-start",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  eyebrow: {
    color: "#FCA5A5",
    fontSize: 12,
    fontWeight: "800",
    letterSpacing: 1.2,
  },
  time: { color: "#fff", fontSize: 42, fontWeight: "800", letterSpacing: -1 },
  alarmId: { color: "#AEB9CD", fontFamily: "monospace", fontSize: 11 },
  label: { color: "#DCE3EF", fontSize: 13, fontWeight: "600" },
  primaryActions: { flexDirection: "row", gap: spacing.sm },
  help: { color: "#DCE3EF", lineHeight: 20 },
});
