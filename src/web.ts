import { WebPlugin } from '@capacitor/core';
import mqtt, { type MqttClient, type IClientOptions, type IClientPublishOptions } from 'mqtt';

import type {
  MqttQuicConnectOptions,
  MqttQuicPingOptions,
  MqttQuicPublishOptions,
  MqttQuicSubscribeOptions,
  MqttQuicSendKeepaliveOptions,
  MqttQuicTestHarnessOptions,
} from './definitions';
import {
  MqttParser,
  buildConnect,
  buildDisconnect,
  buildPingreq,
  buildPublish,
  buildSubscribe,
  buildUnsubscribe,
  type ProtocolLevel,
} from './webMqttCodec';

declare const WebTransport: typeof globalThis extends { WebTransport: infer W } ? W : unknown;

const TAG = '[mqtt-quic-web]';

/**
 * Verbose WebTransport tracing (numbered connect steps, CONNECT hex dump,
 * READ byte counts, parser packet types, publish/subscribe ops). Default: ON.
 *
 * To silence the trace while keeping error logs:
 *   `globalThis.MQTT_QUIC_WT_DEBUG = false;`
 *
 * Errors are always logged regardless of this flag.
 */
function isWtDebugEnabled(): boolean {
  try {
    return (globalThis as unknown as { MQTT_QUIC_WT_DEBUG?: boolean }).MQTT_QUIC_WT_DEBUG !== false;
  } catch {
    return true;
  }
}

function dlog(...args: unknown[]): void {
  if (!isWtDebugEnabled()) return;
  // eslint-disable-next-line no-console
  console.log(TAG, ...args);
}

function elog(...args: unknown[]): void {
  // eslint-disable-next-line no-console
  console.error(TAG, ...args);
}

function hexHead(u: Uint8Array, n = 32): string {
  return Array.from(u.subarray(0, Math.min(n, u.length)))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join(' ');
}

/**
 * Web / browser implementation: MQTT over WebSocket (WSS) or over WebTransport (QUIC).
 * Browsers cannot run ngtcp2/WolfSSL (no UDP). Same API as iOS/Android.
 * - Default: WSS via mqtt.js.
 * - Optional: pass webTransportUrl to use the browser's QUIC (HTTP/3) via WebTransport.
 *
 * The WebTransport path uses an internal hand-rolled MQTT 3.1.1/5.0 codec
 * (`./webMqttCodec`) so it has zero Node `Buffer` / `mqtt-packet` dependency.
 */
export class MqttQuicWeb extends WebPlugin {
  private client: MqttClient | null = null;
  private protocol: 'ws' | 'wss' = 'wss';

  private wt: InstanceType<typeof WebTransport> | null = null;
  private wtWriter: WritableStreamDefaultWriter<Uint8Array> | null = null;
  private wtParser: MqttParser | null = null;
  private wtLevel: ProtocolLevel = 5;
  private wtNextMessageId = 1;
  private wtConnackResolve: (() => void) | null = null;
  private wtConnackReject: ((err: Error) => void) | null = null;
  private wtPendingSuback = new Map<number, { resolve: () => void; reject: (e: Error) => void; topic: string }>();
  private wtPendingUnsuback = new Map<number, { resolve: () => void; reject: (e: Error) => void }>();
  private wtConnected = false;
  /**
   * Single in-flight PINGREQ. MQTT mandates at most one outstanding PINGREQ;
   * concurrent `sendKeepalive` calls share this promise.
   */
  private wtPendingPing: {
    promise: Promise<boolean>;
    resolve: (ok: boolean) => void;
    timer: ReturnType<typeof setTimeout> | null;
  } | null = null;
  /** Background auto-keepalive timer chain (recursive setTimeout). */
  private wtKeepaliveTimer: ReturnType<typeof setTimeout> | null = null;
  private wtKeepaliveSeconds = 0;

  constructor() {
    super();
  }

  /** Web: no UDP; resolves ok if host looks valid. Native uses UDP reachability check. */
  async ping(_options: MqttQuicPingOptions): Promise<{ ok: boolean }> {
    return Promise.resolve({ ok: true });
  }

  /**
   * Send a real PINGREQ and wait for PINGRESP.
   * - WebTransport: writes a PINGREQ packet via the codec and resolves when the
   *   broker's PINGRESP arrives, or `{ ok: false }` after `timeoutMs`.
   * - WSS (`mqtt.js`): the underlying client runs its own keepalive timer, so
   *   we just report whether the socket is currently connected.
   */
  async sendKeepalive(options?: MqttQuicSendKeepaliveOptions): Promise<{ ok: boolean }> {
    if (this.wtConnected && this.wtWriter) {
      const t = options?.timeoutMs;
      const timeoutMs = Math.min(15000, Math.max(1000, t ?? 5000));
      const ok = await this.wtSendPingreq(timeoutMs);
      return { ok };
    }
    return { ok: !!this.client?.connected };
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

  private resolveLevel(options: MqttQuicConnectOptions): ProtocolLevel {
    const pv = options.protocolVersion ?? 'auto';
    if (pv === '3.1.1') return 4;
    return 5; // '5.0' or 'auto'
  }

  private async connectWebTransport(options: MqttQuicConnectOptions): Promise<{ connected: boolean }> {
    try {
      if (this.wtConnected && this.wt) {
        dlog('already connected');
        return { connected: true };
      }
      const url = this.getWebTransportUrl(options);
      dlog('1. new WebTransport', url);
      const transport = new (WebTransport as new (u: string) => InstanceType<typeof WebTransport>)(url);

      dlog('2. awaiting transport.ready');
      await transport.ready;
      dlog('3. transport.ready OK');

      const stream = await transport.createBidirectionalStream();
      dlog('4. bidi stream opened');

      this.wt = transport;
      this.wtWriter = stream.writable.getWriter();
      dlog('5. writer acquired');

      this.wtLevel = this.resolveLevel(options);
      this.wtParser = new MqttParser(this.wtLevel);
      this.wtNextMessageId = 1;
      this.wtPendingSuback.clear();
      this.wtPendingUnsuback.clear();

      let connackTimer: ReturnType<typeof setTimeout> | null = null;
      const connackPromise = new Promise<void>((resolve, reject) => {
        this.wtConnackResolve = () => {
          if (connackTimer) clearTimeout(connackTimer);
          connackTimer = null;
          this.wtConnackResolve = null;
          this.wtConnackReject = null;
          resolve();
        };
        this.wtConnackReject = (err) => {
          if (connackTimer) clearTimeout(connackTimer);
          connackTimer = null;
          this.wtConnackResolve = null;
          this.wtConnackReject = null;
          reject(err);
        };
        connackTimer = setTimeout(() => {
          connackTimer = null;
          const rej = this.wtConnackReject;
          this.wtConnackResolve = null;
          this.wtConnackReject = null;
          elog('CONNACK timeout after 15s');
          if (rej) rej(new Error('WebTransport CONNACK timeout'));
        }, 15_000);
      });

      this.wtParser.on((pkt) => {
        dlog('parser ->', pkt.cmd, pkt.cmd === 'connack' ? `rc=${pkt.reasonCode}` : '');
        if (pkt.cmd === 'connack') {
          if (pkt.reasonCode === 0) {
            this.wtConnected = true;
            const r = this.wtConnackResolve;
            this.wtConnackResolve = null;
            this.wtConnackReject = null;
            if (r) r();
            this.notifyListeners('connected', { connected: true });
          } else {
            const rj = this.wtConnackReject;
            this.wtConnackResolve = null;
            this.wtConnackReject = null;
            if (rj) rj(new Error(`CONNACK rc=${pkt.reasonCode}`));
          }
          return;
        }
        if (pkt.cmd === 'publish') {
          const payload = new TextDecoder().decode(pkt.payload);
          this.notifyListeners('message', { topic: pkt.topic, payload });
          return;
        }
        if (pkt.cmd === 'suback') {
          const cb = this.wtPendingSuback.get(pkt.messageId);
          if (cb) {
            this.wtPendingSuback.delete(pkt.messageId);
            const failed = pkt.reasonCodes.find((rc) => rc >= 0x80);
            if (failed != null) {
              cb.reject(new Error(`SUBACK failure rc=${failed} for ${cb.topic}`));
            } else {
              this.notifyListeners('subscribed', { topic: cb.topic });
              cb.resolve();
            }
          }
          return;
        }
        if (pkt.cmd === 'unsuback') {
          const cb = this.wtPendingUnsuback.get(pkt.messageId);
          if (cb) {
            this.wtPendingUnsuback.delete(pkt.messageId);
            const failed = pkt.reasonCodes.find((rc) => rc >= 0x80);
            if (failed != null) cb.reject(new Error(`UNSUBACK failure rc=${failed}`));
            else cb.resolve();
          }
          return;
        }
        if (pkt.cmd === 'pingresp') {
          const p = this.wtPendingPing;
          if (p) {
            if (p.timer) clearTimeout(p.timer);
            this.wtPendingPing = null;
            p.resolve(true);
          }
          return;
        }
        if (pkt.cmd === 'disconnect') {
          elog('server DISCONNECT rc=', pkt.reasonCode);
          this.failPendingWtOps(new Error(`server DISCONNECT rc=${pkt.reasonCode}`));
        }
      });

      dlog('6. starting read loop');
      void this.wtReadLoop(stream.readable);

      const connectPacket = buildConnect({
        level: this.wtLevel,
        clientId: options.clientId,
        keepalive: options.keepalive ?? 60,
        cleanSession: options.cleanSession ?? true,
        username: options.username || undefined,
        password: options.password || undefined,
        sessionExpiryInterval: this.wtLevel === 5 ? options.sessionExpiryInterval : undefined,
        receiveMaximum: this.wtLevel === 5 ? options.receiveMaximum : undefined,
        maximumPacketSize: this.wtLevel === 5 ? options.maximumPacketSize : undefined,
        topicAliasMaximum: this.wtLevel === 5 ? options.topicAliasMaximum : undefined,
      });
      dlog('7. built CONNECT', connectPacket.length, 'bytes, first32:', hexHead(connectPacket));

      dlog('8. writing CONNECT');
      try {
        await this.wtWriter.write(connectPacket);
      } catch (e) {
        elog('writer.write failed:', (e as Error)?.stack ?? e);
        throw e;
      }
      dlog('9. CONNECT written, awaiting CONNACK');
      await connackPromise;
      dlog('10. CONNACK OK');
      this.wtKeepaliveSeconds = options.keepalive ?? 60;
      this.startWtAutoKeepalive();
      return { connected: true };
    } catch (e) {
      elog('connectWebTransport failed:', (e as Error)?.stack ?? e);
      // best-effort cleanup so a future connect attempt starts clean
      this.stopWtAutoKeepalive();
      this.failPendingWtOps(e instanceof Error ? e : new Error(String(e)));
      try {
        await this.wtWriter?.close();
      } catch {
        /* ignore */
      }
      try {
        this.wt?.close();
      } catch {
        /* ignore */
      }
      this.wt = null;
      this.wtWriter = null;
      this.wtParser = null;
      this.wtConnected = false;
      throw e;
    }
  }

  private failPendingWtOps(err: Error): void {
    if (this.wtConnackReject) {
      const rj = this.wtConnackReject;
      this.wtConnackResolve = null;
      this.wtConnackReject = null;
      rj(err);
    }
    for (const [, cb] of this.wtPendingSuback) cb.reject(err);
    this.wtPendingSuback.clear();
    for (const [, cb] of this.wtPendingUnsuback) cb.reject(err);
    this.wtPendingUnsuback.clear();
    if (this.wtPendingPing) {
      const p = this.wtPendingPing;
      this.wtPendingPing = null;
      if (p.timer) clearTimeout(p.timer);
      p.resolve(false);
    }
  }

  /**
   * Start an internal interval that sends PINGREQ at ~75% of the negotiated
   * keepalive. This guarantees the broker idle-timeout never fires even if the
   * consumer forgets to call `sendKeepalive`. Also matches the WSS path, where
   * `mqtt.js` runs its own internal keepalive timer for free.
   */
  private startWtAutoKeepalive(): void {
    this.stopWtAutoKeepalive();
    const ka = this.wtKeepaliveSeconds;
    if (!ka || ka <= 0) {
      dlog('auto-keepalive: disabled (keepalive=0)');
      return;
    }
    // Steady-state interval at 50% of the negotiated keepalive (vs. spec
    // recommendation of 75-100%) so we beat strict brokers that close at
    // exactly `keepalive` seconds.
    const intervalMs = Math.max(1000, Math.floor(ka * 1000 * 0.5));
    const pingTimeoutMs = Math.max(2000, Math.floor(ka * 1000 * 0.4));
    // First ping fires within ~3s of CONNACK. This catches WebTransport
    // servers with idle timeouts much shorter than the MQTT keepalive
    // (we have observed `WebTransportError: Connection lost` at <10s idle
    // on some HTTP/3 proxies).
    const firstPingMs = Math.min(intervalMs, 3000);
    dlog(
      `auto-keepalive: armed, first=${firstPingMs}ms, interval=${intervalMs}ms, timeout=${pingTimeoutMs}ms`,
    );

    const tick = (): void => {
      this.wtKeepaliveTimer = null;
      if (!this.wtConnected || !this.wtWriter) return;
      void this.wtSendPingreq(pingTimeoutMs).then((ok) => {
        if (!ok) elog('auto-keepalive: PINGRESP timeout');
      });
      if (this.wtConnected) {
        this.wtKeepaliveTimer = setTimeout(tick, intervalMs);
      }
    };
    this.wtKeepaliveTimer = setTimeout(tick, firstPingMs);
  }

  private stopWtAutoKeepalive(): void {
    if (this.wtKeepaliveTimer) {
      clearTimeout(this.wtKeepaliveTimer);
      this.wtKeepaliveTimer = null;
    }
  }

  /**
   * Write a PINGREQ and wait up to `timeoutMs` for the matching PINGRESP.
   * Concurrent callers share the in-flight request (only one PINGREQ may be
   * outstanding per the MQTT spec).
   */
  private async wtSendPingreq(timeoutMs: number): Promise<boolean> {
    if (!this.wtConnected || !this.wtWriter) return false;
    if (this.wtPendingPing) return this.wtPendingPing.promise;

    let resolveFn!: (ok: boolean) => void;
    const promise = new Promise<boolean>((resolve) => {
      resolveFn = resolve;
    });
    const timer = setTimeout(() => {
      if (this.wtPendingPing && this.wtPendingPing.promise === promise) {
        this.wtPendingPing = null;
      }
      resolveFn(false);
    }, timeoutMs);
    this.wtPendingPing = { promise, resolve: resolveFn, timer };

    try {
      dlog('pingreq');
      await this.wtWriter.write(buildPingreq());
    } catch (e) {
      elog('pingreq write failed:', (e as Error)?.stack ?? e);
      if (this.wtPendingPing && this.wtPendingPing.promise === promise) {
        clearTimeout(timer);
        this.wtPendingPing = null;
      }
      return false;
    }
    return promise;
  }

  private async wtReadLoop(readable: ReadableStream<Uint8Array>): Promise<void> {
    const reader = readable.getReader();
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        if (value && value.length > 0) {
          dlog('read', value.length, 'bytes');
          this.wtParser?.feed(value);
        }
      }
      dlog('read loop ended (stream closed)');
    } catch (e) {
      const err = e as Error;
      if (err.name !== 'AbortError') {
        elog('read loop err:', err.stack ?? err);
      }
    } finally {
      try {
        reader.releaseLock();
      } catch {
        /* ignore */
      }
      this.wtConnected = false;
      this.stopWtAutoKeepalive();
      this.failPendingWtOps(new Error('WebTransport stream closed'));
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
        this.client!.on('message', (topic: string, payload: Uint8Array) => {
          const str = new TextDecoder().decode(payload);
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
      this.stopWtAutoKeepalive();
      try {
        if (this.wtWriter) {
          await this.wtWriter.write(buildDisconnect(this.wtLevel));
        }
      } catch {
        /* best-effort */
      }
      try {
        await this.wtWriter?.close();
      } catch {
        /* ignore */
      }
      try {
        this.wt.close();
      } catch {
        /* ignore */
      }
      this.wt = null;
      this.wtWriter = null;
      this.wtParser = null;
      this.wtConnected = false;
      this.failPendingWtOps(new Error('disconnected'));
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
      const qos = (options.qos ?? 0) as 0 | 1 | 2;
      const payload =
        typeof options.payload === 'string'
          ? new TextEncoder().encode(options.payload)
          : options.payload instanceof Uint8Array
            ? options.payload
            : new Uint8Array(options.payload);
      const correlationData =
        options.correlationData == null
          ? undefined
          : typeof options.correlationData === 'string'
            ? new TextEncoder().encode(options.correlationData)
            : options.correlationData;
      const messageId = qos > 0 ? this.nextWtMessageId() : undefined;
      const pkt = buildPublish({
        level: this.wtLevel,
        topic: options.topic,
        payload,
        qos,
        retain: options.retain ?? false,
        messageId,
        messageExpiryInterval: options.messageExpiryInterval,
        contentType: options.contentType,
        responseTopic: options.responseTopic,
        correlationData,
        userProperties: options.userProperties,
      });
      dlog('publish', options.topic, payload.length, 'B');
      await this.wtWriter.write(pkt);
      return { success: true };
    }
    return new Promise((resolve, reject) => {
      if (!this.client?.connected) {
        reject(new Error('Not connected'));
        return;
      }

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
            ? new TextEncoder().encode(options.correlationData)
            : options.correlationData;
      }
      if (options.userProperties?.length) {
        props.userProperties = Object.fromEntries(
          options.userProperties.map((p) => [p.name, p.value])
        );
      }
      if (Object.keys(props).length) opts.properties = props as IClientPublishOptions['properties'];

      // mqtt.js types declare the payload as `string | Buffer`, but its browser
      // build accepts Uint8Array at runtime (Buffer extends Uint8Array). Cast
      // through `unknown` to avoid forcing a Node Buffer polyfill on consumers.
      const payload =
        typeof options.payload === 'string'
          ? options.payload
          : (options.payload as unknown as Parameters<typeof this.client.publish>[1]);

      this.client!.publish(options.topic, payload, opts, (err) => {
        if (err) reject(err);
        else resolve({ success: true });
      });
    });
  }

  async subscribe(options: MqttQuicSubscribeOptions): Promise<{ success: boolean }> {
    if (this.wtConnected && this.wtWriter) {
      const messageId = this.nextWtMessageId();
      const subackPromise = new Promise<void>((resolve, reject) => {
        this.wtPendingSuback.set(messageId, { resolve, reject, topic: options.topic });
      });
      const pkt = buildSubscribe({
        level: this.wtLevel,
        messageId,
        topics: [{ topic: options.topic, qos: (options.qos ?? 0) as 0 | 1 | 2 }],
        subscriptionIdentifier: this.wtLevel === 5 ? options.subscriptionIdentifier : undefined,
      });
      dlog('subscribe', options.topic);
      await this.wtWriter.write(pkt);
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
      const messageId = this.nextWtMessageId();
      const unsubackPromise = new Promise<void>((resolve, reject) => {
        this.wtPendingUnsuback.set(messageId, { resolve, reject });
      });
      const pkt = buildUnsubscribe({ level: this.wtLevel, messageId, topics: [options.topic] });
      await this.wtWriter.write(pkt);
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

  /** Wraps message ID at the MQTT uint16 boundary (1..65535). */
  private nextWtMessageId(): number {
    const id = this.wtNextMessageId;
    this.wtNextMessageId = id >= 0xffff ? 1 : id + 1;
    return id;
  }
}
