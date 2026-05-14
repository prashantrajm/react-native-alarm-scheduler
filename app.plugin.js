const {
  AndroidConfig,
  ConfigPlugin,
  createRunOncePlugin,
  withAndroidManifest,
  withInfoPlist,
} = require('expo/config-plugins');

const pkg = require('./package.json');

const withExpoAlarm = (config, props = {}) => {
  const alarmKitUsageDescription =
    props.alarmKitUsageDescription ||
    'Allow this app to schedule alarms that can alert you at the selected time.';
  const addExactAlarmPermission = props.addExactAlarmPermission !== false;
  const addNotificationPermission = props.addNotificationPermission !== false;

  config = withAndroidManifest(config, (modConfig) => {
    const manifest = modConfig.modResults.manifest;
    if (addExactAlarmPermission) {
      AndroidConfig.Permissions.addPermission(manifest, 'android.permission.SCHEDULE_EXACT_ALARM');
    }
    if (addNotificationPermission) {
      AndroidConfig.Permissions.addPermission(manifest, 'android.permission.POST_NOTIFICATIONS');
    }
    AndroidConfig.Permissions.addPermission(manifest, 'com.android.alarm.permission.SET_ALARM');
    return modConfig;
  });

  config = withInfoPlist(config, (modConfig) => {
    modConfig.modResults.NSAlarmKitUsageDescription = alarmKitUsageDescription;
    return modConfig;
  });

  return config;
};

module.exports = createRunOncePlugin(withExpoAlarm, pkg.name, pkg.version);
