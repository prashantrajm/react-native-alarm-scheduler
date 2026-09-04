import { StyleSheet, Text, View } from "react-native";
import type { AlarmPermissionResponse } from "react-native-alarm-scheduler";

import { colors, spacing } from "../theme";
import { AppButton, Badge, Card } from "./Primitives";

export function PermissionCard(props: {
  permissions?: AlarmPermissionResponse;
  busy: boolean;
  onRequest: () => void;
  onOpenSettings: () => void;
  onOpenFullScreenSettings: () => void;
}) {
  const ready =
    props.permissions?.status === "authorized" &&
    props.permissions.canScheduleExactAlarms &&
    props.permissions.canPostNotifications !== false;
  const fullScreenReady = props.permissions?.canUseFullScreenIntent !== false;

  return (
    <Card>
      <View style={styles.titleRow}>
        <Text style={styles.title}>Native permissions</Text>
        <Badge tone={ready ? "success" : "warning"}>
          {ready ? "Ready" : "Action needed"}
        </Badge>
      </View>
      <Text style={styles.body}>
        {ready
          ? "This device can schedule and present alarms."
          : "Grant alarm and notification access before testing a ring."}
      </Text>
      <View style={styles.actions}>
        <AppButton
          compact
          disabled={props.busy}
          onPress={props.onRequest}
          title="Request access"
        />
        <AppButton
          compact
          disabled={props.busy}
          onPress={props.onOpenSettings}
          title="Alarm settings"
          tone="neutral"
        />
        {!fullScreenReady ? (
          <AppButton
            compact
            disabled={props.busy}
            onPress={props.onOpenFullScreenSettings}
            title="Full-screen access"
            tone="neutral"
          />
        ) : null}
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  titleRow: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  title: { color: colors.text, fontSize: 17, fontWeight: "700" },
  body: { color: colors.textMuted, lineHeight: 20 },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: spacing.sm },
});
