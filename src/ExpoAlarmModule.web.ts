import { registerWebModule, NativeModule } from 'expo';

import { ExpoAlarmModuleEvents } from './ExpoAlarm.types';

class ExpoAlarmModule extends NativeModule<ExpoAlarmModuleEvents> {
  PI = Math.PI;
  async setValueAsync(value: string): Promise<void> {
    this.emit('onChange', { value });
  }
  hello() {
    return 'Hello world! 👋';
  }
}

export default registerWebModule(ExpoAlarmModule, 'ExpoAlarmModule');
