export interface MqttQuicConnectOptions {
  host: string;
  port: number;
  clientId: string;
  username?: string;
  password?: string;
  cleanSession?: boolean;
  keepalive?: number;
  // TLS certificate options (QUIC only)
  caFile?: string;  // Path to CA certificate bundle (PEM)
  caPath?: string;  // Path to CA certificate directory
  // MQTT 5.0 options
  protocolVersion?: '3.1.1' | '5.0' | 'auto';
  sessionExpiryInterval?: number;  // Seconds (MQTT 5.0)
  receiveMaximum?: number;  // MQTT 5.0
  maximumPacketSize?: number;  // MQTT 5.0
  topicAliasMaximum?: number;  // MQTT 5.0
  /**
   * Web only: use QUIC via WebTransport (browser's HTTP/3). Ignored on native.
   *
   * URL path convention (similar to MQTT topic structure): data is available at
   *   https://host:443/mqtt-wt/devices/<deviceId>/<action>/<Path>
   * e.g. https://mqtt.annadata.cloud:443/mqtt-wt/devices/mydevice/subscribe/sensors/temp
   *
   * You can either:
   * - Pass the full URL in webTransportUrl, or
   * - Pass the base URL in webTransportUrl and optional webTransportDeviceId, webTransportAction,
   *   webTransportPath; the plugin will build the path as .../devices/<id>/<action>/<path>.
   */
  webTransportUrl?: string;
  /** Web only: device ID for path (used with webTransportUrl base). */
  webTransportDeviceId?: string;
  /** Web only: action segment, e.g. 'subscribe' | 'publish'. */
  webTransportAction?: string;
  /** Web only: path segment(s), e.g. 'sensors/temp' (like MQTT topic suffix). */
  webTransportPath?: string;
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

export interface MqttQuicTestHarnessOptions {
  host: string;
  port?: number;
  clientId?: string;
  topic?: string;
  payload?: string;
  caFile?: string;
  caPath?: string;
  webTransportUrl?: string;  // Web only: use QUIC via WebTransport
}

export interface MqttQuicPingOptions {
  host: string;
  port?: number;
}

export interface MqttQuicPlugin {
  ping(options: MqttQuicPingOptions): Promise<{ ok: boolean }>;
  connect(options: MqttQuicConnectOptions): Promise<{ connected: boolean }>;
  disconnect(): Promise<void>;
  publish(options: MqttQuicPublishOptions): Promise<{ success: boolean }>;
  subscribe(options: MqttQuicSubscribeOptions): Promise<{ success: boolean }>;
  unsubscribe(options: { topic: string }): Promise<{ success: boolean }>;
  testHarness(options: MqttQuicTestHarnessOptions): Promise<{ success: boolean }>;
}
