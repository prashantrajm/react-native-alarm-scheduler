import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import AlarmScheduler, {
  type AlarmAction,
  type AlarmContext,
  type NativeAlarmDebugState,
  type ScheduledAlarm,
} from 'react-native-alarm-scheduler';
import * as DocumentPicker from 'expo-document-picker';
import {
  Button,
  Platform,
  SafeAreaView,
  ScrollView,
  Text,
  View,
} from 'react-native';

const TEST_ALARM_ID = '00000000-0000-4000-8000-000000000001';

type Snapshot = {
  permissions?: unknown;
  scheduled?: ScheduledAlarm[];
  currentContext?: AlarmContext | null;
  pendingHandoff?: AlarmAction | null;
  pendingActions?: AlarmAction[];
  debug?: NativeAlarmDebugState;
};

export default function App() {
  const [alarmId, setAlarmId] = useState(TEST_ALARM_ID);
  const [snapshot, setSnapshot] = useState<Snapshot>({});
  const [events, setEvents] = useState<string[]>([]);
  const [sound, setSound] = useState<{ name: string; uri: string }>();

  const appendLog = useCallback((label: string, value?: unknown) => {
    const text =
      value === undefined
        ? label
        : `${label}: ${JSON.stringify(value, null, 2)}`;
    console.log(text);
    setEvents((current) => [text, ...current].slice(0, 30));
  }, []);

  const inspect = useCallback(
    async (nextAlarmId = alarmId) => {
      const [
        permissions,
        scheduled,
        currentContext,
        pendingHandoff,
        pendingActions,
        debug,
      ] = await Promise.all([
        AlarmScheduler.getPermissionsAsync(),
        AlarmScheduler.getScheduledAlarmsAsync(),
        AlarmScheduler.getCurrentAlarmContextAsync(),
        AlarmScheduler.getPendingNativeAlarmHandoffAsync(),
        AlarmScheduler.getPendingAlarmActionsAsync(),
        AlarmScheduler.getNativeAlarmDebugStateAsync(nextAlarmId),
      ]);

      const nextSnapshot = {
        permissions,
        scheduled,
        currentContext,
        pendingHandoff,
        pendingActions,
        debug,
      };
      setSnapshot(nextSnapshot);
      appendLog('inspect', nextSnapshot);
      return nextSnapshot;
    },
    [alarmId, appendLog]
  );

  useEffect(() => {
    const triggered = AlarmScheduler.addListener('onAlarmTriggered', (event) => {
      appendLog('event:onAlarmTriggered', event);
      if (event.id) {
        setAlarmId(event.id);
      }
    });
    const action = AlarmScheduler.addListener('onAlarmAction', (event) => {
      appendLog('event:onAlarmAction', event);
      if (event.alarmId) {
        setAlarmId(event.alarmId);
      }
    });
    const state = AlarmScheduler.addListener('onAlarmStateChange', (event) => {
      appendLog('event:onAlarmStateChange', event);
      if (event.id) {
        setAlarmId(event.id);
      }
    });

    inspect().catch((error) => appendLog('initial inspect failed', String(error)));

    return () => {
      triggered.remove();
      action.remove();
      state.remove();
    };
  }, [appendLog, inspect]);

  const currentAlarmId = useMemo(() => {
    return (
      snapshot.pendingHandoff?.alarmId ||
      snapshot.currentContext?.metadata?.alarmId?.toString() ||
      snapshot.currentContext?.id ||
      alarmId
    );
  }, [alarmId, snapshot.currentContext, snapshot.pendingHandoff]);

  const schedulePrimary = useCallback(async () => {
    await AlarmScheduler.cancelNativeAlarmBackupAsync(TEST_ALARM_ID);
    await AlarmScheduler.cancelAlarmAsync(TEST_ALARM_ID);
    await AlarmScheduler.clearPendingAlarmActionsAsync();
    await AlarmScheduler.clearPendingNativeAlarmHandoffAsync();
    await AlarmScheduler.resetNativeAlarmCompletionAsync(TEST_ALARM_ID);

    const nextMinute = new Date(Date.now() + 70_000);
    const scheduled = await AlarmScheduler.scheduleAlarmAsync({
      id: TEST_ALARM_ID,
      hour: nextMinute.getHours(),
      minute: nextMinute.getMinutes(),
      title: 'AlarmKit package test',
      soundUri: sound?.uri,
      ios: {
        alertTitle: 'AlarmKit package test',
        metadata: {
          alarmId: TEST_ALARM_ID,
          source: 'example',
        },
        alertActionMode: 'default',
        stopButtonTitle: 'Open',
        stopIntentBehavior: 'rescheduleImmediate',
        secondaryButtonTitle: 'Open',
        secondaryButtonBehavior: 'openApp',
      },
      // Shared fields (metadata, alertActionMode, stopIntentBehavior, button titles) are inherited
      // from the `ios` block above; only Android-specific behavior is set here.
      android: {
        alertBody: 'Open the app and complete to stop this alarm',
        // iOS relabels its stop button "Open"; on Android the two buttons are distinct.
        stopButtonTitle: 'Stop',
        maxRingDurationSeconds: 120,
      },
    });

    setAlarmId(scheduled.id);
    appendLog('scheduled primary', scheduled);
    await inspect(scheduled.id);
  }, [appendLog, inspect, sound]);

  const pickAlarmSound = useCallback(async () => {
    const result = await DocumentPicker.getDocumentAsync({
      type: 'audio/*',
      copyToCacheDirectory: true,
    });
    if (!result.canceled) {
      const picked = result.assets[0];
      setSound({ name: picked.name, uri: picked.uri });
      appendLog('picked alarm sound', { name: picked.name, uri: picked.uri });
    }
  }, [appendLog]);

  const armBackupFromCurrentState = useCallback(async () => {
    const state = await inspect(currentAlarmId);
    const handoffAlarmId = state.pendingHandoff?.alarmId;
    const contextAlarmId =
      state.currentContext?.metadata?.alarmId?.toString() ||
      state.currentContext?.id;
    const id = handoffAlarmId || contextAlarmId || currentAlarmId;
    const result = await AlarmScheduler.scheduleNativeAlarmBackupAsync(id, 0.1);
    setAlarmId(id);
    appendLog('backup armed', result);
    await inspect(id);
  }, [appendLog, currentAlarmId, inspect]);

  const completeAndCancel = useCallback(async () => {
    await AlarmScheduler.completeNativeAlarmAsync(currentAlarmId);
    await AlarmScheduler.cancelAlarmAsync(currentAlarmId);
    appendLog('completed and canceled', { alarmId: currentAlarmId });
    await inspect(currentAlarmId);
  }, [appendLog, currentAlarmId, inspect]);

  const clearState = useCallback(async () => {
    await AlarmScheduler.cancelNativeAlarmBackupAsync(currentAlarmId);
    await AlarmScheduler.cancelAlarmAsync(currentAlarmId);
    await AlarmScheduler.clearPendingAlarmActionsAsync();
    await AlarmScheduler.clearPendingNativeAlarmHandoffAsync();
    await AlarmScheduler.resetNativeAlarmCompletionAsync(currentAlarmId);
    appendLog('cleared state', { alarmId: currentAlarmId });
    await inspect(currentAlarmId);
  }, [appendLog, currentAlarmId, inspect]);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>Alarm Scheduler</Text>
        <Text style={styles.subheader}>AlarmKit package harness</Text>
        <Group name="Permissions">
          <Button
            title="Request permissions"
            onPress={async () => {
              const result = await AlarmScheduler.requestPermissionsAsync();
              appendLog('permissions requested', result);
              await inspect();
            }}
          />
          <Button title="Inspect native state" onPress={() => inspect()} />
        </Group>
        <Group name="Alarm sound">
          <Text style={styles.mono}>{sound?.name ?? 'System default'}</Text>
          <Button title="Choose audio file" onPress={pickAlarmSound} />
          {sound ? <Button title="Use system default" onPress={() => setSound(undefined)} /> : null}
        </Group>
        <Group name="AlarmKit loop">
          <Text style={styles.mono}>alarmId: {currentAlarmId}</Text>
          <Button title="Schedule primary for next minute" onPress={schedulePrimary} />
          <Button title="Arm backup from current handoff/context" onPress={armBackupFromCurrentState} />
          <Button title="Complete and cancel" onPress={completeAndCancel} />
          <Button title="Clear state" onPress={clearState} />
        </Group>
        <Group name="Snapshot">
          <Text style={styles.mono}>{JSON.stringify(snapshot, null, 2)}</Text>
        </Group>
        <Group name="Event log">
          {events.length === 0 ? (
            <Text>No events yet</Text>
          ) : (
            events.map((event, index) => (
              <Text key={`${index}-${event.slice(0, 20)}`} style={styles.mono}>
                {event}
              </Text>
            ))
          )}
        </Group>
        {Platform.OS === 'android' ? (
          <Group name="Android Clock">
            <Button
              title="Open system alarm app"
              onPress={async () => {
                await AlarmScheduler.openSystemAlarmAppAsync();
              }}
            />
          </Group>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

function Group(props: { name: string; children: ReactNode }) {
  return (
    <View style={styles.group}>
      <Text style={styles.groupHeader}>{props.name}</Text>
      {props.children}
    </View>
  );
}

const styles = {
  header: {
    fontSize: 30,
    marginHorizontal: 20,
    marginTop: 20,
  },
  subheader: {
    fontSize: 16,
    marginHorizontal: 20,
    marginTop: 4,
  },
  groupHeader: {
    fontSize: 20,
    marginBottom: 16,
  },
  group: {
    margin: 20,
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 20,
    gap: 12,
  },
  mono: {
    fontFamily: Platform.select({ ios: 'Menlo', android: 'monospace' }),
    fontSize: 12,
  },
  container: {
    flex: 1,
    backgroundColor: '#eee',
  },
};
