import type { MqttQuicConnectOptions, MqttQuicPublishOptions, MqttQuicSubscribeOptions } from './definitions';

/**
 * Web implementation: MQTT over WebSocket (WSS) fallback.
 * Browsers cannot use ngtcp2/QUIC; use mqtt.js or similar over WSS.
 * Phase 4 will wire this to mqtt.js when running in browser.
 */
export class MqttQuicWeb {
  async connect(_options: MqttQuicConnectOptions): Promise<{ connected: boolean }> {
    return { connected: false };
  }

  async disconnect(): Promise<void> {}

  async publish(_options: MqttQuicPublishOptions): Promise<{ success: boolean }> {
    return { success: false };
  }

  async subscribe(_options: MqttQuicSubscribeOptions): Promise<{ success: boolean }> {
    return { success: false };
  }

  async unsubscribe(_options: { topic: string }): Promise<{ success: boolean }> {
    return { success: false };
  }
}
