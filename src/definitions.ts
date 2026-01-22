export interface MqttQuicConnectOptions {
  host: string;
  port: number;
  clientId: string;
  username?: string;
  password?: string;
  cleanSession?: boolean;
  keepalive?: number;
  // MQTT 5.0 options
  protocolVersion?: '3.1.1' | '5.0' | 'auto';
  sessionExpiryInterval?: number;  // Seconds (MQTT 5.0)
  receiveMaximum?: number;  // MQTT 5.0
  maximumPacketSize?: number;  // MQTT 5.0
  topicAliasMaximum?: number;  // MQTT 5.0
}

export interface MqttQuicPublishOptions {
  topic: string;
  payload: string | Uint8Array;
  qos?: 0 | 1 | 2;
  retain?: boolean;
  // MQTT 5.0 properties
  messageExpiryInterval?: number;  // Seconds
  contentType?: string;
  responseTopic?: string;
  correlationData?: string | Uint8Array;
  userProperties?: Array<{ name: string; value: string }>;
}

export interface MqttQuicSubscribeOptions {
  topic: string;
  qos?: 0 | 1 | 2;
  // MQTT 5.0
  subscriptionIdentifier?: number;
}

export type MqttQuicConnectionState = 'disconnected' | 'connecting' | 'connected' | 'reconnecting' | 'error';

export interface MqttQuicPlugin {
  connect(options: MqttQuicConnectOptions): Promise<{ connected: boolean }>;
  disconnect(): Promise<void>;
  publish(options: MqttQuicPublishOptions): Promise<{ success: boolean }>;
  subscribe(options: MqttQuicSubscribeOptions): Promise<{ success: boolean }>;
  unsubscribe(options: { topic: string }): Promise<{ success: boolean }>;
}
