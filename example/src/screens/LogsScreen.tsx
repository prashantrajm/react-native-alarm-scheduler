import { ScrollView, StyleSheet, Text, View } from "react-native";

import { formatDateTime } from "../format";
import { colors, spacing } from "../theme";
import type { AlarmController } from "../useAlarmController";
import {
  AppButton,
  Card,
  EmptyState,
  ScreenHeader,
  SectionTitle,
} from "../components/Primitives";

export function LogsScreen(props: { controller: AlarmController }) {
  const { controller } = props;
  const isBusy = Boolean(controller.busy);

  return (
    <ScrollView contentContainerStyle={styles.content}>
      <ScreenHeader
        subtitle="Events and low-level recovery controls live here, away from the alarm flow."
        title="Logs"
      />

      <Card>
        <SectionTitle>Native diagnostics</SectionTitle>
        <Text style={styles.label}>Selected alarm</Text>
        <Text numberOfLines={1} style={styles.mono}>
          {controller.selectedAlarmId ?? "None"}
        </Text>
        <View style={styles.actions}>
          <AppButton
            compact
            disabled={isBusy}
            onPress={() => void controller.refresh()}
            title="Refresh state"
          />
          <AppButton
            compact
            disabled={isBusy || !controller.selectedAlarmId}
            onPress={() => void controller.armBackup()}
            title="Arm 10s recovery"
            tone="neutral"
          />
          <AppButton
            compact
            disabled={isBusy || !controller.selectedAlarmId}
            onPress={() => void controller.cancelBackup()}
            title="Cancel recovery"
            tone="neutral"
          />
          <AppButton
            compact
            disabled={isBusy || !controller.selectedAlarmId}
            onPress={() => void controller.resetCompletion()}
            title="Reset completion"
            tone="neutral"
          />
          <AppButton
            compact
            disabled={isBusy || !controller.selectedAlarmId}
            onPress={() => void controller.clearBypass()}
            title="Clear bypass"
            tone="neutral"
          />
          <AppButton
            compact
            disabled={isBusy}
            onPress={() => void controller.clearPendingActions()}
            title="Clear actions"
            tone="neutral"
          />
          <AppButton
            compact
            disabled={isBusy}
            onPress={() => void controller.clearHandoff()}
            title="Clear handoff"
            tone="neutral"
          />
        </View>
        <Text style={styles.snapshot}>
          {JSON.stringify(
            {
              permissions: controller.snapshot.permissions,
              currentContext: controller.snapshot.currentContext,
              pendingHandoff: controller.snapshot.pendingHandoff,
              pendingActions: controller.snapshot.pendingActions,
              debug: controller.snapshot.debug,
            },
            null,
            2
          )}
        </Text>
      </Card>

      <SectionTitle
        action={
          <AppButton
            compact
            onPress={controller.clearLogs}
            title="Clear"
            tone="ghost"
          />
        }
      >
        Event log ({controller.logs.length})
      </SectionTitle>
      {controller.logs.length === 0 ? (
        <EmptyState
          title="No events yet"
          body="Schedule an alarm and interact with its native UI."
        />
      ) : (
        controller.logs.map((entry) => (
          <Card
            key={entry.id}
            style={entry.level === "error" ? styles.errorCard : undefined}
          >
            <View style={styles.logHeader}>
              <Text
                style={[
                  styles.logTitle,
                  entry.level === "error" && styles.errorText,
                ]}
              >
                {entry.title}
              </Text>
              <Text style={styles.logTime}>
                {formatDateTime(entry.timestamp)}
              </Text>
            </View>
            {entry.detail !== undefined ? (
              <Text selectable style={styles.mono}>
                {JSON.stringify(entry.detail, null, 2)}
              </Text>
            ) : null}
          </Card>
        ))
      )}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: spacing.md,
    paddingBottom: spacing.xl,
    paddingHorizontal: spacing.lg,
  },
  label: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: "700",
    textTransform: "uppercase",
  },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: spacing.sm },
  snapshot: {
    backgroundColor: colors.dark,
    borderRadius: 12,
    color: "#DCE3EF",
    fontFamily: "monospace",
    fontSize: 11,
    lineHeight: 17,
    padding: spacing.md,
  },
  logHeader: { gap: 3 },
  logTitle: { color: colors.text, fontSize: 15, fontWeight: "700" },
  logTime: { color: colors.textMuted, fontSize: 11 },
  mono: {
    color: colors.textMuted,
    fontFamily: "monospace",
    fontSize: 11,
    lineHeight: 17,
  },
  errorCard: { backgroundColor: colors.dangerSoft },
  errorText: { color: colors.danger },
});
