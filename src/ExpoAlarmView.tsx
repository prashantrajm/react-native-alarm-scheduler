import { requireNativeView } from 'expo';
import * as React from 'react';

import { ExpoAlarmViewProps } from './ExpoAlarm.types';

const NativeView: React.ComponentType<ExpoAlarmViewProps> =
  requireNativeView('ExpoAlarm');

export default function ExpoAlarmView(props: ExpoAlarmViewProps) {
  return <NativeView {...props} />;
}
