import { StatusBar, StyleSheet, View } from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";

import { TabBar } from "./src/components/TabBar";
import { AlarmsScreen } from "./src/screens/AlarmsScreen";
import { LogsScreen } from "./src/screens/LogsScreen";
import { OccurrencesScreen } from "./src/screens/OccurrencesScreen";
import { colors } from "./src/theme";
import { useAlarmController } from "./src/useAlarmController";

export default function App() {
  const controller = useAlarmController();

  return (
    <SafeAreaProvider>
      <SafeAreaView edges={["top", "bottom"]} style={styles.safeArea}>
        <StatusBar barStyle="dark-content" />
        <View style={styles.content}>
          {controller.tab === "alarms" ? (
            <AlarmsScreen controller={controller} />
          ) : null}
          {controller.tab === "occurrences" ? (
            <OccurrencesScreen controller={controller} />
          ) : null}
          {controller.tab === "logs" ? (
            <LogsScreen controller={controller} />
          ) : null}
        </View>
        <TabBar activeTab={controller.tab} onChange={controller.setTab} />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    flex: 1,
  },
});
