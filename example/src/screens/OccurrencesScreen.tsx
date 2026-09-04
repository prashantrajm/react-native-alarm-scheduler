import { useMemo, useState } from "react";
import { ScrollView, StyleSheet, Text } from "react-native";

import { ChoiceRow } from "../components/ChoiceRow";
import { OccurrenceCard } from "../components/OccurrenceCard";
import {
  AppButton,
  EmptyState,
  ScreenHeader,
  SectionTitle,
} from "../components/Primitives";
import { colors, spacing } from "../theme";
import type { AlarmController } from "../useAlarmController";

type Filter = "active" | "history" | "all";

export function OccurrencesScreen(props: { controller: AlarmController }) {
  const { controller } = props;
  const [filter, setFilter] = useState<Filter>("active");
  const occurrences = useMemo(
    () =>
      controller.snapshot.occurrences.filter((occurrence) => {
        const active =
          occurrence.phase === "scheduled" || occurrence.phase === "ringing";
        if (filter === "active") return active;
        if (filter === "history") return !active;
        return true;
      }),
    [controller.snapshot.occurrences, filter]
  );

  return (
    <ScrollView contentContainerStyle={styles.content}>
      <ScreenHeader
        subtitle="Every native delivery, including primary, deferred, and follow-up occurrences."
        title="Occurrences"
      />
      <ChoiceRow
        onChange={setFilter}
        options={[
          { label: "Active", value: "active" },
          { label: "History", value: "history" },
          { label: "All", value: "all" },
        ]}
        value={filter}
      />
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
        {occurrences.length} {filter === "all" ? "total" : filter}
      </SectionTitle>
      {occurrences.length === 0 ? (
        <EmptyState
          body={
            filter === "active"
              ? "Schedule an alarm or create a deferred occurrence."
              : "Resolved occurrences appear here."
          }
          title={`No ${filter} occurrences`}
        />
      ) : (
        occurrences.map((occurrence) => (
          <OccurrenceCard
            busy={Boolean(controller.busy)}
            key={occurrence.occurrenceId}
            occurrence={occurrence}
            onCancel={() => void controller.cancelOccurrence(occurrence)}
          />
        ))
      )}
      <Text style={styles.note}>
        Occurrence records are native lifecycle state. App statistics and
        product history should be stored separately.
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  content: {
    gap: spacing.md,
    paddingBottom: spacing.xl,
    paddingHorizontal: spacing.lg,
  },
  note: {
    color: colors.textMuted,
    fontSize: 12,
    lineHeight: 18,
    padding: spacing.sm,
  },
});
