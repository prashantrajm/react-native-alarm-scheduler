import { Pressable, StyleSheet, Text, View } from "react-native";

import { colors, spacing } from "../theme";
import type { AppTab } from "../types";

const tabs: Array<{ id: AppTab; label: string; symbol: string }> = [
  { id: "alarms", label: "Alarms", symbol: "◷" },
  { id: "occurrences", label: "Occurrences", symbol: "↻" },
  { id: "logs", label: "Logs", symbol: "≡" },
];

export function TabBar(props: {
  activeTab: AppTab;
  onChange: (tab: AppTab) => void;
}) {
  return (
    <View style={styles.container}>
      {tabs.map((tab) => {
        const active = tab.id === props.activeTab;
        return (
          <Pressable
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            key={tab.id}
            onPress={() => props.onChange(tab.id)}
            style={styles.tab}
          >
            <Text style={[styles.symbol, active && styles.active]}>
              {tab.symbol}
            </Text>
            <Text style={[styles.label, active && styles.active]}>
              {tab.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.surface,
    borderTopColor: colors.border,
    borderTopWidth: StyleSheet.hairlineWidth,
    flexDirection: "row",
    paddingBottom: spacing.xs,
    paddingTop: spacing.sm,
  },
  tab: { alignItems: "center", flex: 1, gap: 2, paddingVertical: spacing.xs },
  symbol: { color: colors.textMuted, fontSize: 22, fontWeight: "700" },
  label: { color: colors.textMuted, fontSize: 11, fontWeight: "600" },
  active: { color: colors.primary },
});
