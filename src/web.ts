import { WebPlugin } from '@capacitor/core';
import mqtt, { type MqttClient, type IClientOptions, type IClientPublishOptions } from 'mqtt';
import * as mqttPacket from 'mqtt-packet';
import type { Packet, IConnectPacket, IPublishPacket, ISubscribePacket, IUnsubscribePacket } from 'mqtt-packet';
import type {
  MqttQuicConnectOptions,
  MqttQuicPingOptions,
  MqttQuicPublishOptions,
  MqttQuicSubscribeOptions,
  MqttQuicSendKeepaliveOptions,
  MqttQuicTestHarnessOptions,
} from './definitions';

declare const WebTransport: typeof globalThis extends { WebTransport: infer W } ? W : unknown;

/**
 * Web / browser implementation: MQTT over WebSocket (WSS) or over WebTransport (QUIC).
 * Browsers cannot run ngtcp2/WolfSSL (no UDP). Same API as iOS/Android.
 * - Default: WSS via mqtt.js.
 * - Optional: pass webTransportUrl to use the browser's QUIC (HTTP/3) via WebTransport.
 */
export class MqttQuicWeb extends WebPlugin {
  private client: MqttClient | null = null;
  private protocol: 'ws' | 'wss' = 'wss';

  private wt: InstanceType<typeof WebTransport> | null = null;
  private wtWriter: WritableStreamDefaultWriter<Uint8Array> | null = null;
  private wtReadAbort: AbortController | null = null;
  private wtParser: ReturnType<typeof mqttPacket.parser> | null = null;
  private wtReadBuffer: Uint8Array[] = [];
  private wtNextMessageId = 1;
  private wtConnackResolve: ((value: void) => void) | null = null;
  private wtPendingSuback = new Map<number, { resolve: () => void; topic: string }>();
  private wtPendingUnsuback = new Map<number, { resolve: () => void }>();
  private wtConnected = false;

  constructor() {
    super();
  }

  /** Web: no UDP; resolves ok if host looks valid. Native uses UDP reachability check. */
  async ping(_options: MqttQuicPingOptions): Promise<{ ok: boolean }> {
    return Promise.resolve({ ok: true });
  }

  /** Web: mqtt.js/WT handle keepalive; return ok if connected. */
  async sendKeepalive(_options?: MqttQuicSendKeepaliveOptions): Promise<{ ok: boolean }> {
    const connected = this.client?.connected ?? this.wtConnected;
    return Promise.resolve({ ok: !!connected });
  }

  async connect(options: MqttQuicConnectOptions): Promise<{ connected: boolean }> {
    if (options.webTransportUrl && typeof WebTransport !== 'undefined') {
      return this.connectWebTransport(options);
    }
    return this.connectWSS(options);
  }

  /**
   * Build WebTransport URL. If path components are provided, appends
   * /devices/<deviceId>/<action>/<path> (like MQTT topic structure).
   */
  private getWebTransportUrl(options: MqttQuicConnectOptions): string {
    let base = (options.webTransportUrl ?? '').replace(/\/$/, '');
    const deviceId = options.webTransportDeviceId;
    const action = options.webTransportAction;
    const path = options.webTransportPath;
    if (deviceId != null && deviceId !== '' && action != null && action !== '') {
      const pathSegment = path != null && path !== '' ? `/${path.replace(/^\/+/, '')}` : '';
      base = `${base}/devices/${encodeURIComponent(deviceId)}/${encodeURIComponent(action)}${pathSegment}`;
    }
    return base;
  }

  private async connectWebTransport(options: MqttQuicConnectOptions): Promise<{ connected: boolean }> {
    if (this.wtConnected && this.wt) {
      return { connected: true };
    }
    const url = this.getWebTransportUrl(options);
    const transport = new (WebTransport as new (u: string) => InstanceType<typeof WebTransport>)(url);
    await transport.ready;
    const stream = await transport.createBidirectionalStream();
    this.wt = transport;
    this.wtWriter = stream.writable.getWriter();
    this.wtReadAbort = new AbortController();
    this.wtParser = mqttPacket.parser();
    this.wtReadBuffer = [];
    this.wtNextMessageId = 1;
    this.wtPendingSuback.clear();
    this.wtPendingUnsuback.clear();

    let connackTimer: ReturnType<typeof setTimeout> | null = null;
    const connackPromise = new Promise<void>((resolve, reject) => {
      this.wtConnackResolve = () => {
        if (connackTimer) clearTimeout(connackTimer);
        resolve();
      };
      connackTimer = setTimeout(() => {
        connackTimer = null;
        this.wtConnackResolve = null;
        reject(new Error('WebTransport CONNACK timeout'));
      }, 15_000);
    });

    this.wtParser.on('packet', (packet: Packet) => {
      if (packet.cmd === 'connack') {
        this.wtConnected = true;
        if (this.wtConnackResolve) {
          const r = this.wtConnackResolve;
          this.wtConnackResolve = null;
          r();
        }
        this.notifyListeners('connected', { connected: true });
        return;
      }
      if (packet.cmd === 'publish') {
        const p = packet as IPublishPacket;
        const payload = typeof p.payload === 'string' ? p.payload : (p.payload && Buffer.isBuffer(p.payload) ? p.payload.toString('utf8') : String(p.payload));
        this.notifyListeners('message', { topic: p.topic, payload });
        return;
      }
      if (packet.cmd === 'suback' && packet.messageId !== undefined) {
        const cb = this.wtPendingSuback.get(packet.messageId);
        if (cb) {
          this.wtPendingSuback.delete(packet.messageId);
          this.notifyListeners('subscribed', { topic: cb.topic });
          cb.resolve();
        }
        return;
      }
      if (packet.cmd === 'unsuback' && packet.messageId !== undefined) {
        const cb = this.wtPendingUnsuback.get(packet.messageId);
        if (cb) {
          this.wtPendingUnsuback.delete(packet.messageId);
          cb.resolve();
        }
      }
    });

    this.wtReadLoop(stream.readable);

    const pv = options.protocolVersion ?? 'auto';
    const ver: 4 | 5 = pv === '3.1.1' ? 4 : 5;
    const connectPacket: IConnectPacket = {
      cmd: 'connect',
      clientId: options.clientId,
      protocolVersion: ver,
      protocolId: 'MQTT',
      clean: options.cleanSession ?? true,
      keepalive: options.keepalive ?? 20,
      username: options.username,
      password: options.password ? Buffer.from(options.password, 'utf8') : undefined,
      properties: ver === 5 && options.sessionExpiryInterval != null ? { sessionExpiryInterval: options.sessionExpiryInterval } : undefined,
    };
    const buf = mqttPacket.generate(connectPacket);
    await this.wtWrite(buf);
    await connackPromise;
    return { connected: true };
  }

  private async wtWrite(data: Buffer | Uint8Array): Promise<void> {
    if (!this.wtWriter) return;
    const chunk = data instanceof Buffer ? new Uint8Array(data) : data;
    await this.wtWriter.write(chunk);
  }

  private async wtReadLoop(readable: ReadableStream<Uint8Array>): Promise<void> {
    const reader = readable.getReader();
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (this.wtParser && value.length > 0) {
          this.wtParser.parse(Buffer.from(value));
        }
      }
    } catch (e) {
      if ((e as Error).name !== 'AbortError') this.wtConnected = false;
    } finally {
      reader.releaseLock();
    }
  }

  private async connectWSS(options: MqttQuicConnectOptions): Promise<{ connected: boolean }> {
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
        keepalive: options.keepalive ?? 20,
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
        this.client!.on('message', (topic: string, payload: Buffer) => {
          const str = payload.toString('utf8');
          this.notifyListeners('message', { topic, payload: str });
        });
        this.notifyListeners('connected', { connected: true });
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
    if (this.wt) {
      this.wtReadAbort?.abort();
      try {
        await this.wtWriter?.close();
        await this.wt.close();
      } catch (_) {}
      this.wt = null;
      this.wtWriter = null;
      this.wtParser = null;
      this.wtConnected = false;
      this.wtPendingSuback.clear();
      this.wtPendingUnsuback.clear();
      return;
    }
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
    if (this.wtConnected && this.wtWriter) {
      const payload = typeof options.payload === 'string' ? Buffer.from(options.payload, 'utf8') : Buffer.from(options.payload);
      const packet: IPublishPacket = {
        cmd: 'publish',
        topic: options.topic,
        payload,
        qos: (options.qos ?? 0) as 0 | 1 | 2,
        dup: false,
        retain: options.retain ?? false,
        messageId: (options.qos ?? 0) > 0 ? this.wtNextMessageId++ : undefined,
        properties: options.contentType || options.responseTopic || options.userProperties?.length
          ? {
              contentType: options.contentType,
              responseTopic: options.responseTopic,
              correlationData: options.correlationData != null ? Buffer.from(options.correlationData as ArrayBuffer) : undefined,
              userProperties: options.userProperties?.length ? Object.fromEntries(options.userProperties.map((p) => [p.name, p.value])) : undefined,
              messageExpiryInterval: options.messageExpiryInterval,
            }
          : undefined,
      };
      const buf = mqttPacket.generate(packet);
      await this.wtWrite(buf);
      return { success: true };
    }
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
    if (this.wtConnected && this.wtWriter) {
      const messageId = this.wtNextMessageId++;
      const subackPromise = new Promise<void>((resolve) => {
        this.wtPendingSuback.set(messageId, { resolve, topic: options.topic });
      });
      const packet: ISubscribePacket = {
        cmd: 'subscribe',
        messageId,
        subscriptions: [{ topic: options.topic, qos: (options.qos ?? 0) as 0 | 1 | 2 }],
        properties: options.subscriptionIdentifier != null ? { subscriptionIdentifier: options.subscriptionIdentifier } : undefined,
      };
      await this.wtWrite(mqttPacket.generate(packet));
      await subackPromise;
      return { success: true };
    }
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
        else {
          this.notifyListeners('subscribed', { topic: options.topic });
          resolve({ success: true });
        }
      });
    });
  }

  async unsubscribe(options: { topic: string }): Promise<{ success: boolean }> {
    if (this.wtConnected && this.wtWriter) {
      const messageId = this.wtNextMessageId++;
      const unsubackPromise = new Promise<void>((resolve) => {
        this.wtPendingUnsuback.set(messageId, { resolve });
      });
      const packet: IUnsubscribePacket = {
        cmd: 'unsubscribe',
        messageId,
        unsubscriptions: [options.topic],
      };
      await this.wtWrite(mqttPacket.generate(packet));
      await unsubackPromise;
      return { success: true };
    }
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

  async testHarness(options: MqttQuicTestHarnessOptions): Promise<{ success: boolean }> {
    const host = options.host;
    const port = options.port ?? 1884;
    const clientId = options.clientId ?? 'AcharyaAnnadata';
    const topic = options.topic ?? 'test/topic';
    const payload = options.payload ?? 'Hello QUIC!';

    try {
      await this.connect({
        host,
        port,
        clientId,
        cleanSession: true,
        keepalive: 20,
        ...(options.webTransportUrl && { webTransportUrl: options.webTransportUrl }),
      });
      await this.subscribe({ topic, qos: 0 });
      await this.publish({ topic, payload, qos: 0 });
      await this.disconnect();
      return { success: true };
    } catch (error) {
      throw error instanceof Error ? error : new Error(String(error));
    }
  }
}
