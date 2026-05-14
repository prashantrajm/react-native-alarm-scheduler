import { NativeModule, requireNativeModule } from 'expo';

import { ExpoAlarmModuleEvents } from './ExpoAlarm.types';

declare class ExpoAlarmModule extends NativeModule<ExpoAlarmModuleEvents> {
  PI: number;
  hello(): string;
  setValueAsync(value: string): Promise<void>;
}

// This call loads the native module object from the JSI.
export default requireNativeModule<ExpoAlarmModule>('ExpoAlarm');
