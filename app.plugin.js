const {
  AndroidConfig,
  createRunOncePlugin,
  IOSConfig,
  PluginError,
  withAndroidManifest,
  withInfoPlist,
  withXcodeProject,
} = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

const pkg = require('./package.json');

const withExpoAlarm = (config, props = {}) => {
  const alarmKitUsageDescription =
    props.alarmKitUsageDescription ||
    'Allow this app to schedule alarms that can alert you at the selected time.';
  const addExactAlarmPermission = props.addExactAlarmPermission !== false;
  const addNotificationPermission = props.addNotificationPermission !== false;
  // Opt-in: USE_EXACT_ALARM is granted without a user prompt, but Google Play only allows it for
  // apps whose core function is an alarm clock or calendar.
  const addUseExactAlarmPermission = props.addUseExactAlarmPermission === true;
  const iosAlarmSounds = normalizeIosAlarmSounds(props.iosAlarmSounds);

  config = withAndroidManifest(config, (modConfig) => {
    const manifest = modConfig.modResults.manifest;
    if (addExactAlarmPermission) {
      AndroidConfig.Permissions.addPermission(manifest, 'android.permission.SCHEDULE_EXACT_ALARM');
    }
    if (addNotificationPermission) {
      AndroidConfig.Permissions.addPermission(manifest, 'android.permission.POST_NOTIFICATIONS');
    }
    if (addUseExactAlarmPermission) {
      AndroidConfig.Permissions.addPermission(manifest, 'android.permission.USE_EXACT_ALARM');
    }
    AndroidConfig.Permissions.addPermission(manifest, 'com.android.alarm.permission.SET_ALARM');
    return modConfig;
  });

  config = withInfoPlist(config, (modConfig) => {
    modConfig.modResults.NSAlarmKitUsageDescription = alarmKitUsageDescription;
    modConfig.modResults.NSSupportsLiveActivities = true;
    return modConfig;
  });

  if (iosAlarmSounds.length > 0) {
    config = withXcodeProject(config, (modConfig) => {
      const project = modConfig.modResults;
      const projectRoot = modConfig.modRequest.projectRoot;
      const platformProjectRoot = modConfig.modRequest.platformProjectRoot;
      IOSConfig.XcodeUtils.ensureGroupRecursively(project, 'Resources');

      iosAlarmSounds.forEach((sound) => {
        const absolutePath = path.resolve(projectRoot, sound);
        if (!fs.existsSync(absolutePath)) {
          throw new PluginError(
            `Alarm sound file does not exist: ${sound}`,
            pkg.name
          );
        }

        IOSConfig.XcodeUtils.addResourceFileToGroup({
          filepath: path.relative(platformProjectRoot, absolutePath),
          groupName: 'Resources',
          project,
          isBuildFile: true,
          verbose: true,
        });
      });

      return modConfig;
    });
  }

  return config;
};

function normalizeIosAlarmSounds(value) {
  if (value == null) {
    return [];
  }
  if (!Array.isArray(value) || !value.every((item) => typeof item === 'string')) {
    throw new PluginError('iosAlarmSounds must be an array of file paths.', pkg.name);
  }
  return value;
}

module.exports = createRunOncePlugin(withExpoAlarm, pkg.name, pkg.version);
