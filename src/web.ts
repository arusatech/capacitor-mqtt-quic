import mqtt, { type MqttClient, type IClientOptions, type IClientPublishOptions } from 'mqtt';
import type {
  MqttQuicConnectOptions,
  MqttQuicPublishOptions,
  MqttQuicSubscribeOptions,
} from './definitions';

/**
 * Web/PWA implementation: MQTT over WebSocket (WSS).
 * Browsers cannot use ngtcp2/QUIC; mqtt.js over WSS is used as fallback.
 */
export class MqttQuicWeb {
  private client: MqttClient | null = null;
  private protocol: 'ws' | 'wss' = 'wss';

  async connect(options: MqttQuicConnectOptions): Promise<{ connected: boolean }> {
    return new Promise((resolve, reject) => {
      if (this.client?.connected) {
        resolve({ connected: true });
        return;
      }
      if (this.client && !this.client.connected) {
        reject(new Error('already connecting'));
        return;
      }

      const port = options.port ?? 1884;
      this.protocol = port === 8884 || port === 443 ? 'wss' : 'ws';
      const url = `${this.protocol}://${options.host}:${port}`;

      const connectOpts: IClientOptions = {
        clientId: options.clientId,
        username: options.username,
        password: options.password,
        clean: options.cleanSession ?? true,
        keepalive: options.keepalive ?? 60,
        reconnectPeriod: 0,
        connectTimeout: 30_000,
      };

      const pv = options.protocolVersion ?? 'auto';
      if (pv === '5.0') {
        connectOpts.protocolVersion = 5;
        connectOpts.properties = {
          sessionExpiryInterval: options.sessionExpiryInterval,
        };
      } else if (pv === '3.1.1') {
        connectOpts.protocolVersion = 4;
      } else {
        connectOpts.protocolVersion = 5;
        connectOpts.properties = options.sessionExpiryInterval != null
          ? { sessionExpiryInterval: options.sessionExpiryInterval }
          : undefined;
      }

      try {
        this.client = mqtt.connect(url, connectOpts);
      } catch (e) {
        reject(e instanceof Error ? e.message : 'Connect failed');
        return;
      }

      const onConnect = () => {
        this.client!.removeListener('error', onError);
        resolve({ connected: true });
      };

      const onError = (err: Error) => {
        this.client?.removeListener('connect', onConnect);
        reject(err.message);
      };

      this.client.once('connect', onConnect);
      this.client.once('error', onError);
    });
  }

  async disconnect(): Promise<void> {
    return new Promise((resolve) => {
      if (!this.client) {
        resolve();
        return;
      }
      const c = this.client;
      this.client = null;
      c.end(false, () => resolve());
      c.removeAllListeners();
    });
  }

  async publish(options: MqttQuicPublishOptions): Promise<{ success: boolean }> {
    return new Promise((resolve, reject) => {
      if (!this.client?.connected) {
        reject(new Error('Not connected'));
        return;
      }

      const payload =
        typeof options.payload === 'string'
          ? options.payload
          : Buffer.from(options.payload);

      const opts: IClientPublishOptions = {
        qos: (options.qos ?? 0) as 0 | 1 | 2,
        retain: options.retain ?? false,
      };
      const props: Record<string, unknown> = {};
      if (options.messageExpiryInterval != null) props.messageExpiryInterval = options.messageExpiryInterval;
      if (options.contentType) props.contentType = options.contentType;
      if (options.responseTopic) props.responseTopic = options.responseTopic;
      if (options.correlationData != null) {
        props.correlationData =
          typeof options.correlationData === 'string'
            ? Buffer.from(options.correlationData, 'utf8')
            : Buffer.from(options.correlationData);
      }
      if (options.userProperties?.length) {
        props.userProperties = Object.fromEntries(
          options.userProperties.map((p) => [p.name, p.value])
        );
      }
      if (Object.keys(props).length) opts.properties = props as IClientPublishOptions['properties'];

      this.client!.publish(options.topic, payload, opts, (err) => {
        if (err) reject(err);
        else resolve({ success: true });
      });
    });
  }

  async subscribe(options: MqttQuicSubscribeOptions): Promise<{ success: boolean }> {
    return new Promise((resolve, reject) => {
      if (!this.client?.connected) {
        reject(new Error('Not connected'));
        return;
      }

      const opts: { qos: 0 | 1 | 2; properties?: { subscriptionIdentifier: number } } = {
        qos: (options.qos ?? 0) as 0 | 1 | 2,
      };
      if (options.subscriptionIdentifier != null) {
        opts.properties = { subscriptionIdentifier: options.subscriptionIdentifier };
      }

      this.client!.subscribe(options.topic, opts, (err) => {
        if (err) reject(err);
        else resolve({ success: true });
      });
    });
  }

  async unsubscribe(options: { topic: string }): Promise<{ success: boolean }> {
    return new Promise((resolve, reject) => {
      if (!this.client?.connected) {
        reject(new Error('Not connected'));
        return;
      }

      this.client!.unsubscribe(options.topic, (err) => {
        if (err) reject(err);
        else resolve({ success: true });
      });
    });
  }
}
