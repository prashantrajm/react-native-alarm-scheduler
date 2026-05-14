import * as React from 'react';

import { ExpoAlarmViewProps } from './ExpoAlarm.types';

export default function ExpoAlarmView(props: ExpoAlarmViewProps) {
  return (
    <div>
      <iframe
        style={{ flex: 1 }}
        src={props.url}
        onLoad={() => props.onLoad({ nativeEvent: { url: props.url } })}
      />
    </div>
  );
}
