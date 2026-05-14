import { useEvent } from 'expo';
import ExpoAlarm from 'react-native-alarm-scheduler';
import { Button, Platform, SafeAreaView, ScrollView, Text, View } from 'react-native';

export default function App() {
  const alarmEvent = useEvent(ExpoAlarm, 'onAlarmTriggered');

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.container}>
        <Text style={styles.header}>Expo Alarm</Text>
        <Group name="Permissions">
          <Button
            title="Check permissions"
            onPress={async () => {
              console.log(await ExpoAlarm.getPermissionsAsync());
            }}
          />
          <Button
            title="Request permissions"
            onPress={async () => {
              console.log(await ExpoAlarm.requestPermissionsAsync());
            }}
          />
        </Group>
        <Group name="Native schedule">
          <Button
            title="Schedule alarm for next minute"
            onPress={async () => {
              const nextMinute = new Date(Date.now() + 60_000);
              console.log(await ExpoAlarm.scheduleAlarmAsync({
                hour: nextMinute.getHours(),
                minute: nextMinute.getMinutes(),
                title: 'Expo Alarm example',
              }));
            }}
          />
        </Group>
        <Group name="Events">
          <Text>{alarmEvent ? JSON.stringify(alarmEvent) : 'No alarm event yet'}</Text>
        </Group>
        {Platform.OS === 'android' ? (
          <Group name="Android Clock">
            <Button
              title="Open system alarm app"
              onPress={async () => {
                await ExpoAlarm.openSystemAlarmAppAsync();
              }}
            />
          </Group>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

function Group(props: { name: string; children: React.ReactNode }) {
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
    margin: 20,
  },
  groupHeader: {
    fontSize: 20,
    marginBottom: 20,
  },
  group: {
    margin: 20,
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 20,
  },
  container: {
    flex: 1,
    backgroundColor: '#eee',
  },
};
