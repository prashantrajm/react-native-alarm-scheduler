import { Pressable, StyleSheet, Text, View } from "react-native";

import { colors, spacing } from "../theme";

export function ChoiceRow<T extends string | number>(props: {
  options: Array<{ label: string; value: T }>;
  value: T;
  onChange: (value: T) => void;
}) {
  return (
    <View style={styles.row}>
      {props.options.map((option) => {
        const active = option.value === props.value;
        return (
          <Pressable
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            key={option.value}
            onPress={() => props.onChange(option.value)}
            style={[styles.choice, active && styles.choiceActive]}
          >
            <Text style={[styles.label, active && styles.labelActive]}>
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", flexWrap: "wrap", gap: spacing.sm },
  choice: {
    backgroundColor: colors.surfaceMuted,
    borderRadius: 10,
    paddingHorizontal: spacing.md,
    paddingVertical: 9,
  },
  choiceActive: { backgroundColor: colors.primary },
  label: { color: colors.text, fontSize: 13, fontWeight: "700" },
  labelActive: { color: "#fff" },
});
