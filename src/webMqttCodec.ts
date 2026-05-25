/**
 * Pure-browser MQTT 3.1.1 + 5.0 codec.
 *
 * No Node `Buffer`, no `mqtt-packet` dependency. Built on `Uint8Array` +
 * `TextEncoder`/`TextDecoder` so it works in any browser (and inside
 * WebTransport bidirectional streams) without polyfills.
 *
 * Only the subset of MQTT 5 properties surfaced by `MqttQuicConnectOptions`,
 * `MqttQuicPublishOptions`, and `MqttQuicSubscribeOptions` is encoded; inbound
 * properties on PUBLISH/CONNACK/SUBACK/UNSUBACK/PUBACK are skipped (their
 * length is honored so the rest of the packet stays aligned) since the public
 * API does not currently expose them on inbound events.
 */

export type ProtocolLevel = 4 | 5;

export interface ConnectInput {
  level: ProtocolLevel;
  clientId: string;
  keepalive?: number;
  cleanSession?: boolean;
  username?: string;
  password?: string | Uint8Array;
  // v5 properties (ignored when level === 4)
  sessionExpiryInterval?: number;
  receiveMaximum?: number;
  maximumPacketSize?: number;
  topicAliasMaximum?: number;
}

export interface PublishInput {
  level: ProtocolLevel;
  topic: string;
  payload: Uint8Array;
  qos: 0 | 1 | 2;
  retain?: boolean;
  dup?: boolean;
  messageId?: number;
  // v5
  messageExpiryInterval?: number;
  contentType?: string;
  responseTopic?: string;
  correlationData?: Uint8Array;
  userProperties?: Array<{ name: string; value: string }>;
}

export interface SubscribeInput {
  level: ProtocolLevel;
  messageId: number;
  topics: Array<{ topic: string; qos: 0 | 1 | 2 }>;
  // v5
  subscriptionIdentifier?: number;
}

export interface UnsubscribeInput {
  level: ProtocolLevel;
  messageId: number;
  topics: string[];
}

export type MqttPacket =
  | { cmd: 'connack'; sessionPresent: boolean; reasonCode: number }
  | {
      cmd: 'publish';
      topic: string;
      payload: Uint8Array;
      qos: 0 | 1 | 2;
      retain: boolean;
      dup: boolean;
      messageId?: number;
    }
  | { cmd: 'puback'; messageId: number; reasonCode: number }
  | { cmd: 'suback'; messageId: number; reasonCodes: number[] }
  | { cmd: 'unsuback'; messageId: number; reasonCodes: number[] }
  | { cmd: 'pingresp' }
  | { cmd: 'disconnect'; reasonCode: number };

const TEXT_ENC = new TextEncoder();
const TEXT_DEC = new TextDecoder();

// ---------- low-level encoders ----------

function encVarint(n: number): Uint8Array {
  if (n < 0 || n > 268_435_455) throw new Error('VBI out of range: ' + n);
  const out: number[] = [];
  let v = n;
  do {
    let b = v & 0x7f;
    v = v >>> 7;
    if (v > 0) b |= 0x80;
    out.push(b);
  } while (v > 0);
  return new Uint8Array(out);
}

function encU16(n: number): Uint8Array {
  return new Uint8Array([(n >> 8) & 0xff, n & 0xff]);
}

function encU32(n: number): Uint8Array {
  return new Uint8Array([
    (n >>> 24) & 0xff,
    (n >>> 16) & 0xff,
    (n >>> 8) & 0xff,
    n & 0xff,
  ]);
}

function encStr(s: string): Uint8Array {
  const bytes = TEXT_ENC.encode(s);
  if (bytes.length > 0xffff) throw new Error('UTF-8 string too long: ' + bytes.length);
  const out = new Uint8Array(2 + bytes.length);
  out[0] = (bytes.length >> 8) & 0xff;
  out[1] = bytes.length & 0xff;
  out.set(bytes, 2);
  return out;
}

function encBin(bin: Uint8Array): Uint8Array {
  if (bin.length > 0xffff) throw new Error('binary data too long: ' + bin.length);
  const out = new Uint8Array(2 + bin.length);
  out[0] = (bin.length >> 8) & 0xff;
  out[1] = bin.length & 0xff;
  out.set(bin, 2);
  return out;
}

function concat(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

// ---------- low-level decoders ----------

interface Cursor { off: number; }

function decVarint(buf: Uint8Array, cur: Cursor): number | null {
  let multiplier = 1;
  let value = 0;
  let i = cur.off;
  let byte: number;
  do {
    if (i >= buf.length) return null;
    byte = buf[i++];
    value += (byte & 0x7f) * multiplier;
    if (multiplier > 128 * 128 * 128) throw new Error('Malformed VBI');
    multiplier *= 128;
  } while ((byte & 0x80) !== 0);
  cur.off = i;
  return value;
}

function decU16(buf: Uint8Array, cur: Cursor): number {
  const v = (buf[cur.off] << 8) | buf[cur.off + 1];
  cur.off += 2;
  return v;
}

function decU32(buf: Uint8Array, cur: Cursor): number {
  const v =
    (buf[cur.off] * 0x1000000) +
    ((buf[cur.off + 1] << 16) | (buf[cur.off + 2] << 8) | buf[cur.off + 3]);
  cur.off += 4;
  return v;
}

function decStr(buf: Uint8Array, cur: Cursor): string {
  const len = decU16(buf, cur);
  const s = TEXT_DEC.decode(buf.subarray(cur.off, cur.off + len));
  cur.off += len;
  return s;
}

// ---------- v5 property encoders ----------

const PROP = {
  MESSAGE_EXPIRY_INTERVAL: 0x02,
  CONTENT_TYPE: 0x03,
  RESPONSE_TOPIC: 0x08,
  CORRELATION_DATA: 0x09,
  SUBSCRIPTION_IDENTIFIER: 0x0b,
  SESSION_EXPIRY_INTERVAL: 0x11,
  RECEIVE_MAXIMUM: 0x21,
  TOPIC_ALIAS_MAXIMUM: 0x22,
  USER_PROPERTY: 0x26,
  MAXIMUM_PACKET_SIZE: 0x27,
} as const;

function buildConnectProps(o: ConnectInput): Uint8Array {
  const parts: Uint8Array[] = [];
  if (o.sessionExpiryInterval != null) {
    parts.push(new Uint8Array([PROP.SESSION_EXPIRY_INTERVAL]));
    parts.push(encU32(o.sessionExpiryInterval));
  }
  if (o.receiveMaximum != null) {
    parts.push(new Uint8Array([PROP.RECEIVE_MAXIMUM]));
    parts.push(encU16(o.receiveMaximum));
  }
  if (o.maximumPacketSize != null) {
    parts.push(new Uint8Array([PROP.MAXIMUM_PACKET_SIZE]));
    parts.push(encU32(o.maximumPacketSize));
  }
  if (o.topicAliasMaximum != null) {
    parts.push(new Uint8Array([PROP.TOPIC_ALIAS_MAXIMUM]));
    parts.push(encU16(o.topicAliasMaximum));
  }
  return wrapPropsSection(parts);
}

function buildPublishProps(o: PublishInput): Uint8Array {
  const parts: Uint8Array[] = [];
  if (o.messageExpiryInterval != null) {
    parts.push(new Uint8Array([PROP.MESSAGE_EXPIRY_INTERVAL]));
    parts.push(encU32(o.messageExpiryInterval));
  }
  if (o.contentType) {
    parts.push(new Uint8Array([PROP.CONTENT_TYPE]));
    parts.push(encStr(o.contentType));
  }
  if (o.responseTopic) {
    parts.push(new Uint8Array([PROP.RESPONSE_TOPIC]));
    parts.push(encStr(o.responseTopic));
  }
  if (o.correlationData) {
    parts.push(new Uint8Array([PROP.CORRELATION_DATA]));
    parts.push(encBin(o.correlationData));
  }
  if (o.userProperties && o.userProperties.length) {
    for (const up of o.userProperties) {
      parts.push(new Uint8Array([PROP.USER_PROPERTY]));
      parts.push(encStr(up.name));
      parts.push(encStr(up.value));
    }
  }
  return wrapPropsSection(parts);
}

function buildSubscribeProps(o: SubscribeInput): Uint8Array {
  const parts: Uint8Array[] = [];
  if (o.subscriptionIdentifier != null) {
    parts.push(new Uint8Array([PROP.SUBSCRIPTION_IDENTIFIER]));
    parts.push(encVarint(o.subscriptionIdentifier));
  }
  return wrapPropsSection(parts);
}

function emptyPropsSection(): Uint8Array {
  return new Uint8Array([0x00]);
}

function wrapPropsSection(parts: Uint8Array[]): Uint8Array {
  const body = concat(parts);
  const len = encVarint(body.length);
  const out = new Uint8Array(len.length + body.length);
  out.set(len, 0);
  out.set(body, len.length);
  return out;
}

// ---------- packet builders ----------

export function buildConnect(o: ConnectInput): Uint8Array {
  const proto = encStr('MQTT');
  const lvl = new Uint8Array([o.level]);
  let flags = 0;
  if (o.cleanSession ?? true) flags |= 0x02;
  if (o.username != null) flags |= 0x80;
  if (o.password != null) flags |= 0x40;
  const flagsByte = new Uint8Array([flags]);
  const ka = encU16(o.keepalive ?? 60);

  const variableHeaderParts: Uint8Array[] = [proto, lvl, flagsByte, ka];
  if (o.level === 5) {
    variableHeaderParts.push(buildConnectProps(o));
  }

  const payloadParts: Uint8Array[] = [encStr(o.clientId)];
  if (o.username != null) payloadParts.push(encStr(o.username));
  if (o.password != null) {
    const pw = o.password instanceof Uint8Array ? o.password : TEXT_ENC.encode(o.password);
    payloadParts.push(encBin(pw));
  }

  const variableHeader = concat(variableHeaderParts);
  const payload = concat(payloadParts);
  const remaining = variableHeader.length + payload.length;
  return concat([new Uint8Array([0x10]), encVarint(remaining), variableHeader, payload]);
}

export function buildPublish(o: PublishInput): Uint8Array {
  let firstByte = 0x30;
  if (o.dup) firstByte |= 0x08;
  firstByte |= (o.qos & 0x03) << 1;
  if (o.retain) firstByte |= 0x01;

  const topic = encStr(o.topic);
  const mid =
    o.qos > 0 && o.messageId != null ? encU16(o.messageId) : new Uint8Array(0);
  const props = o.level === 5 ? buildPublishProps(o) : new Uint8Array(0);

  const remaining = topic.length + mid.length + props.length + o.payload.length;
  return concat([
    new Uint8Array([firstByte]),
    encVarint(remaining),
    topic,
    mid,
    props,
    o.payload,
  ]);
}

export function buildSubscribe(o: SubscribeInput): Uint8Array {
  const mid = encU16(o.messageId);
  const props = o.level === 5 ? buildSubscribeProps(o) : new Uint8Array(0);
  const filterParts: Uint8Array[] = [];
  for (const t of o.topics) {
    filterParts.push(encStr(t.topic));
    // v3 options byte = qos only; v5 options byte uses lower 2 bits for qos as well.
    filterParts.push(new Uint8Array([t.qos & 0x03]));
  }
  const filters = concat(filterParts);
  const remaining = mid.length + props.length + filters.length;
  return concat([new Uint8Array([0x82]), encVarint(remaining), mid, props, filters]);
}

export function buildUnsubscribe(o: UnsubscribeInput): Uint8Array {
  const mid = encU16(o.messageId);
  const props = o.level === 5 ? emptyPropsSection() : new Uint8Array(0);
  const topicParts = o.topics.map(encStr);
  const filters = concat(topicParts);
  const remaining = mid.length + props.length + filters.length;
  return concat([new Uint8Array([0xa2]), encVarint(remaining), mid, props, filters]);
}

export function buildPingreq(): Uint8Array {
  return new Uint8Array([0xc0, 0x00]);
}

export function buildDisconnect(level: ProtocolLevel): Uint8Array {
  if (level === 5) {
    // Reason code 0x00 (Normal disconnection); no properties.
    return new Uint8Array([0xe0, 0x01, 0x00]);
  }
  return new Uint8Array([0xe0, 0x00]);
}

// ---------- streaming parser ----------

type PacketHandler = (pkt: MqttPacket) => void;

export class MqttParser {
  private level: ProtocolLevel;
  private buffer: Uint8Array = new Uint8Array(0);
  private handlers: PacketHandler[] = [];

  constructor(level: ProtocolLevel) {
    this.level = level;
  }

  on(handler: PacketHandler): void {
    this.handlers.push(handler);
  }

  feed(chunk: Uint8Array): void {
    if (!chunk || chunk.length === 0) return;
    const merged = new Uint8Array(this.buffer.length + chunk.length);
    merged.set(this.buffer, 0);
    merged.set(chunk, this.buffer.length);
    this.buffer = merged;
    this.drain();
  }

  private drain(): void {
    while (this.buffer.length >= 2) {
      const firstByte = this.buffer[0];
      const cur: Cursor = { off: 1 };
      const remaining = decVarint(this.buffer, cur);
      if (remaining == null) return; // wait for more bytes
      const headerLen = cur.off;
      const totalLen = headerLen + remaining;
      if (this.buffer.length < totalLen) return;

      const body = this.buffer.subarray(headerLen, totalLen);
      this.buffer = this.buffer.subarray(totalLen);

      const cmdNibble = (firstByte >> 4) & 0x0f;
      const pkt = this.decodePacket(cmdNibble, firstByte, body);
      if (pkt) this.emit(pkt);
    }
  }

  private emit(pkt: MqttPacket): void {
    for (const h of this.handlers) {
      try {
        h(pkt);
      } catch (e) {
        // Handler errors must not break the parser loop.
        // eslint-disable-next-line no-console
        console.error('[mqtt-quic-web] parser handler error:', e);
      }
    }
  }

  private decodePacket(
    cmd: number,
    firstByte: number,
    body: Uint8Array
  ): MqttPacket | null {
    switch (cmd) {
      case 2:
        return this.decodeConnack(body);
      case 3:
        return this.decodePublish(firstByte, body);
      case 4:
        return this.decodePuback(body);
      case 9:
        return this.decodeSuback(body);
      case 11:
        return this.decodeUnsuback(body);
      case 13:
        return { cmd: 'pingresp' };
      case 14:
        return this.decodeDisconnect(body);
      default:
        // eslint-disable-next-line no-console
        console.warn('[mqtt-quic-web] unknown packet type:', cmd);
        return null;
    }
  }

  private decodeConnack(body: Uint8Array): MqttPacket {
    const cur: Cursor = { off: 0 };
    const flags = body[cur.off++];
    const reasonCode = body[cur.off++];
    if (this.level === 5) this.skipProperties(body, cur);
    return { cmd: 'connack', sessionPresent: (flags & 0x01) === 0x01, reasonCode };
  }

  private decodePublish(firstByte: number, body: Uint8Array): MqttPacket {
    const qos = ((firstByte >> 1) & 0x03) as 0 | 1 | 2;
    const dup = (firstByte & 0x08) !== 0;
    const retain = (firstByte & 0x01) !== 0;
    const cur: Cursor = { off: 0 };
    const topic = decStr(body, cur);
    let messageId: number | undefined;
    if (qos > 0) messageId = decU16(body, cur);
    if (this.level === 5) this.skipProperties(body, cur);
    const payload = body.slice(cur.off);
    return { cmd: 'publish', topic, payload, qos, retain, dup, messageId };
  }

  private decodePuback(body: Uint8Array): MqttPacket {
    const cur: Cursor = { off: 0 };
    const messageId = decU16(body, cur);
    let reasonCode = 0;
    if (this.level === 5 && cur.off < body.length) {
      reasonCode = body[cur.off++];
      if (cur.off < body.length) this.skipProperties(body, cur);
    }
    return { cmd: 'puback', messageId, reasonCode };
  }

  private decodeSuback(body: Uint8Array): MqttPacket {
    const cur: Cursor = { off: 0 };
    const messageId = decU16(body, cur);
    if (this.level === 5) this.skipProperties(body, cur);
    const reasonCodes: number[] = [];
    while (cur.off < body.length) reasonCodes.push(body[cur.off++]);
    return { cmd: 'suback', messageId, reasonCodes };
  }

  private decodeUnsuback(body: Uint8Array): MqttPacket {
    const cur: Cursor = { off: 0 };
    const messageId = decU16(body, cur);
    if (this.level === 5) this.skipProperties(body, cur);
    const reasonCodes: number[] = [];
    while (cur.off < body.length) reasonCodes.push(body[cur.off++]);
    return { cmd: 'unsuback', messageId, reasonCodes };
  }

  private decodeDisconnect(body: Uint8Array): MqttPacket {
    if (body.length === 0) return { cmd: 'disconnect', reasonCode: 0 };
    const cur: Cursor = { off: 0 };
    const reasonCode = body[cur.off++];
    if (this.level === 5 && cur.off < body.length) this.skipProperties(body, cur);
    return { cmd: 'disconnect', reasonCode };
  }

  /** Advance `cur` past a v5 properties section without interpreting it. */
  private skipProperties(body: Uint8Array, cur: Cursor): void {
    const propsLen = decVarint(body, cur);
    if (propsLen == null) {
      // Should not happen on a fully-buffered packet; treat as zero-length.
      return;
    }
    cur.off += propsLen;
  }
}
