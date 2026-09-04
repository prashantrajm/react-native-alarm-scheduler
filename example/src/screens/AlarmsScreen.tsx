import {
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
} from "react-native";

import type { AlarmController } from "../useAlarmController";
import { colors, spacing } from "../theme";
import { ActiveAlarmCard } from "../components/ActiveAlarmCard";
import { AlarmCard } from "../components/AlarmCard";
import { ChoiceRow } from "../components/ChoiceRow";
import { PermissionCard } from "../components/PermissionCard";
import {
  AppButton,
  Card,
  EmptyState,
  ScreenHeader,
  SectionTitle,
} from "../components/Primitives";

export function AlarmsScreen(props: { controller: AlarmController }) {
  const { controller } = props;
  const isBusy = Boolean(controller.busy);

  return (
    <ScrollView
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      <ScreenHeader
        subtitle="Schedule alarms, open the app from native UI, and resolve the active occurrence."
        title="Alarms"
      />

      {controller.error ? (
        <Card style={styles.errorCard}>
          <View style={styles.errorHeader}>
            <Text style={styles.errorTitle}>Action failed</Text>
            <AppButton
              compact
              onPress={controller.clearError}
              title="Dismiss"
              tone="danger"
            />
          </View>
          <Text style={styles.errorBody}>{controller.error}</Text>
        </Card>
      ) : null}

      {controller.isAlerting ? (
        <ActiveAlarmCard
          alarmId={controller.activeAlarmId}
          busy={isBusy}
          delaySeconds={controller.relatedDelaySeconds}
          occurrence={controller.activeOccurrence}
          onComplete={() => {
            if (controller.activeOccurrence) {
              void controller.resolveOccurrence(
                controller.activeOccurrence,
                "complete"
              );
            }
          }}
          onCompleteNative={() => void controller.completeNative()}
          onDefer={() => {
            if (controller.activeOccurrence) {
              void controller.resolveOccurrence(
                controller.activeOccurrence,
                "defer"
              );
            }
          }}
          onDelayChange={controller.setRelatedDelaySeconds}
          onFollowUp={() => {
            if (controller.activeOccurrence) {
              void controller.resolveOccurrence(
                controller.activeOccurrence,
                "followUp"
              );
            }
          }}
        />
      ) : null}

      <PermissionCard
        busy={isBusy}
        onOpenFullScreenSettings={() =>
          void controller.openFullScreenSettings()
        }
        onOpenSettings={() => void controller.openAlarmSettings()}
        onRequest={() => void controller.requestPermissions()}
        permissions={controller.snapshot.permissions}
      />

      <Card>
        <SectionTitle>New alarm</SectionTitle>
        <TextInput
          accessibilityLabel="Alarm title"
          onChangeText={controller.setTitle}
          placeholder="Alarm title"
          placeholderTextColor={colors.textMuted}
          style={styles.input}
          value={controller.title}
        />
        <Text style={styles.label}>Ring in</Text>
        <ChoiceRow
          onChange={controller.setDelaySeconds}
          options={[
            { label: "15 sec", value: 15 },
            { label: "1 min", value: 60 },
            { label: "5 min", value: 300 },
          ]}
          value={controller.delaySeconds}
        />
        <View style={styles.switchRow}>
          <View style={styles.switchCopy}>
            <Text style={styles.switchTitle}>Require app completion</Text>
            <Text style={styles.help}>
              The alarm keeps ringing after opening the app, so defer and
              follow-up actions can be tested.
            </Text>
          </View>
          <Switch
            onValueChange={controller.setRequiresAppCompletion}
            trackColor={{ false: colors.border, true: colors.primarySoft }}
            thumbColor={
              controller.requiresAppCompletion ? colors.primary : "#fff"
            }
            value={controller.requiresAppCompletion}
          />
        </View>
        <View style={styles.switchRow}>
          <View style={styles.switchCopy}>
            <Text style={styles.switchTitle}>Silent alarm</Text>
            <Text style={styles.help}>
              Suppress audio while preserving vibration and native alarm UI.
            </Text>
          </View>
          <Switch
            onValueChange={controller.setSilent}
            trackColor={{ false: colors.border, true: colors.primarySoft }}
            thumbColor={controller.silent ? colors.primary : "#fff"}
            value={controller.silent}
          />
        </View>
        <View style={styles.soundRow}>
          <View style={styles.soundCopy}>
            <Text style={styles.label}>Sound</Text>
            <Text numberOfLines={1} style={styles.help}>
              {controller.silent
                ? "No audio"
                : controller.sound?.name ?? "System default"}
            </Text>
          </View>
          <AppButton
            compact
            onPress={() => void controller.pickSound()}
            title="Choose file"
            tone="neutral"
          />
          {controller.sound ? (
            <AppButton
              compact
              onPress={controller.clearSound}
              title="Reset"
              tone="ghost"
            />
          ) : null}
        </View>
        <AppButton
          disabled={isBusy}
          loading={controller.busy === "Alarm scheduled"}
          onPress={() => void controller.scheduleAlarm()}
          title="Schedule alarm"
        />
      </Card>

      <SectionTitle
        action={
          <AppButton
            compact
            onPress={() => void controller.refresh()}
            title="Refresh"
            tone="ghost"
          />
        }
      >
        Scheduled alarms ({controller.snapshot.scheduled.length})
      </SectionTitle>
      {controller.snapshot.scheduled.length === 0 ? (
        <EmptyState
          title="No alarms scheduled"
          body="Create a short test alarm above to begin."
        />
      ) : (
        controller.snapshot.scheduled.map((alarm) => (
          <AlarmCard
            alarm={alarm}
            busy={isBusy}
            key={alarm.id}
            onCancel={() => void controller.cancelAlarm(alarm)}
            onInspect={() => {
              controller.setSelectedAlarmId(alarm.id);
              controller.setTab("logs");
              void controller.refresh(alarm.id);
            }}
          />
        ))
      )}

      {controller.platform === "android" ? (
        <Card>
          <SectionTitle>Android system Clock</SectionTitle>
          <Text style={styles.help}>
            These actions exercise the separate Android Clock integration rather
            than app-owned alarms.
          </Text>
          <View style={styles.actions}>
            <AppButton
              compact
              disabled={isBusy}
              onPress={() => void controller.setSystemAlarm()}
              title="Add system alarm"
              tone="neutral"
            />
            <AppButton
              compact
              disabled={isBusy}
              onPress={() => void controller.openSystemAlarmApp()}
              title="Open Clock"
              tone="neutral"
            />
          </View>
        </Card>
      ) : null}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: spacing.md,
    paddingBottom: spacing.xl,
    paddingHorizontal: spacing.lg,
  },
  errorCard: {
    backgroundColor: colors.dangerSoft,
    borderColor: colors.dangerSoft,
  },
  errorHeader: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  errorTitle: { color: colors.danger, fontSize: 16, fontWeight: "800" },
  errorBody: { color: colors.danger, lineHeight: 20 },
  input: {
    backgroundColor: colors.background,
    borderColor: colors.border,
    borderRadius: 12,
    borderWidth: 1,
    color: colors.text,
    fontSize: 16,
    minHeight: 50,
    paddingHorizontal: spacing.md,
  },
  label: { color: colors.text, fontSize: 14, fontWeight: "700" },
  help: { color: colors.textMuted, fontSize: 13, lineHeight: 19 },
  switchRow: { alignItems: "center", flexDirection: "row", gap: spacing.md },
  switchCopy: { flex: 1, gap: 3 },
  switchTitle: { color: colors.text, fontSize: 15, fontWeight: "700" },
  soundRow: { alignItems: "center", flexDirection: "row", gap: spacing.sm },
  soundCopy: { flex: 1 },
  actions: { flexDirection: "row", flexWrap: "wrap", gap: spacing.sm },
});
