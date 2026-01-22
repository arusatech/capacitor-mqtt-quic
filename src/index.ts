import { registerPlugin } from '@capacitor/core';
import type { MqttQuicPlugin } from './definitions';

const MqttQuic = registerPlugin<MqttQuicPlugin>('MqttQuic', {
  web: () => import('./web').then((m) => new m.MqttQuicWeb()),
});

export * from './definitions';
export { MqttQuic };
