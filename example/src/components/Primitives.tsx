import type { ReactNode } from "react";
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
  type StyleProp,
  type ViewStyle,
} from "react-native";

import { colors, spacing } from "../theme";

export function ScreenHeader(props: { title: string; subtitle: string }) {
  return (
    <View style={styles.header}>
      <Text style={styles.title}>{props.title}</Text>
      <Text style={styles.subtitle}>{props.subtitle}</Text>
    </View>
  );
}

export function Card(props: {
  children: ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  return <View style={[styles.card, props.style]}>{props.children}</View>;
}

export function SectionTitle(props: {
  children: ReactNode;
  action?: ReactNode;
}) {
  return (
    <View style={styles.sectionTitleRow}>
      <Text style={styles.sectionTitle}>{props.children}</Text>
      {props.action}
    </View>
  );
}

type ButtonTone = "primary" | "neutral" | "danger" | "ghost";

export function AppButton(props: {
  title: string;
  onPress: () => void;
  tone?: ButtonTone;
  disabled?: boolean;
  loading?: boolean;
  compact?: boolean;
}) {
  const tone = props.tone ?? "primary";
  return (
    <Pressable
      accessibilityRole="button"
      disabled={props.disabled || props.loading}
      onPress={props.onPress}
      style={({ pressed }) => [
        styles.button,
        props.compact && styles.buttonCompact,
        buttonStyles[tone],
        pressed && styles.buttonPressed,
        (props.disabled || props.loading) && styles.buttonDisabled,
      ]}
    >
      {props.loading ? (
        <ActivityIndicator color={tone === "primary" ? "#fff" : colors.text} />
      ) : null}
      <Text style={[styles.buttonText, buttonTextStyles[tone]]}>
        {props.title}
      </Text>
    </Pressable>
  );
}

export function Badge(props: {
  children: ReactNode;
  tone?: "neutral" | "success" | "warning" | "danger" | "primary";
}) {
  const tone = props.tone ?? "neutral";
  return (
    <View style={[styles.badge, badgeStyles[tone]]}>
      <Text style={[styles.badgeText, badgeTextStyles[tone]]}>
        {props.children}
      </Text>
    </View>
  );
}

export function EmptyState(props: { title: string; body: string }) {
  return (
    <Card style={styles.emptyState}>
      <Text style={styles.emptyTitle}>{props.title}</Text>
      <Text style={styles.emptyBody}>{props.body}</Text>
    </Card>
  );
}

const styles = StyleSheet.create({
  header: {
    paddingHorizontal: spacing.xl,
    paddingTop: spacing.lg,
    paddingBottom: spacing.lg,
  },
  title: {
    color: colors.text,
    fontSize: 30,
    fontWeight: "800",
    letterSpacing: -0.6,
  },
  subtitle: {
    color: colors.textMuted,
    fontSize: 15,
    lineHeight: 21,
    marginTop: spacing.xs,
  },
  card: {
    backgroundColor: colors.surface,
    borderColor: colors.border,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    padding: spacing.lg,
    gap: spacing.md,
  },
  sectionTitleRow: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
  },
  sectionTitle: {
    color: colors.text,
    fontSize: 18,
    fontWeight: "700",
  },
  button: {
    alignItems: "center",
    borderRadius: 12,
    flexDirection: "row",
    gap: spacing.sm,
    justifyContent: "center",
    minHeight: 48,
    paddingHorizontal: spacing.lg,
  },
  buttonCompact: {
    minHeight: 38,
    paddingHorizontal: spacing.md,
  },
  buttonPressed: { opacity: 0.75 },
  buttonDisabled: { opacity: 0.45 },
  buttonText: { fontSize: 15, fontWeight: "700" },
  badge: {
    alignSelf: "flex-start",
    borderRadius: 999,
    paddingHorizontal: 9,
    paddingVertical: 4,
  },
  badgeText: { fontSize: 12, fontWeight: "700" },
  emptyState: { alignItems: "center", paddingVertical: 28 },
  emptyTitle: { color: colors.text, fontSize: 17, fontWeight: "700" },
  emptyBody: { color: colors.textMuted, lineHeight: 20, textAlign: "center" },
});

const buttonStyles = StyleSheet.create({
  primary: { backgroundColor: colors.primary },
  neutral: { backgroundColor: colors.surfaceMuted },
  danger: { backgroundColor: colors.dangerSoft },
  ghost: { backgroundColor: "transparent" },
});

const buttonTextStyles = StyleSheet.create({
  primary: { color: "#fff" },
  neutral: { color: colors.text },
  danger: { color: colors.danger },
  ghost: { color: colors.primary },
});

const badgeStyles = StyleSheet.create({
  neutral: { backgroundColor: colors.surfaceMuted },
  success: { backgroundColor: colors.successSoft },
  warning: { backgroundColor: colors.warningSoft },
  danger: { backgroundColor: colors.dangerSoft },
  primary: { backgroundColor: colors.primarySoft },
});

const badgeTextStyles = StyleSheet.create({
  neutral: { color: colors.textMuted },
  success: { color: colors.success },
  warning: { color: colors.warning },
  danger: { color: colors.danger },
  primary: { color: colors.primary },
});
