# P0 & P1 Implementation Changelog

## P0 – Critical (Segfault / crash prevention)

### iOS (MQTTClient.swift, MqttQuicPlugin.swift)

1. **Message loop**
   - Use `[weak self]` in the loop `Task` and re-fetch `reader` each iteration under lock; `break` if `nil`.
   - Re-fetch `writer` under lock when sending PUBACK (don’t hold a stale reference).
2. **Disconnect**
   - Cancel message-loop task, `await task?.value`, then clear refs.
   - Use a local `writer` copy to send DISCONNECT and close; avoid using cleared refs.
3. **Packet ID**
   - `nextPacketIdUsed()` now uses the lock for increment and wrap.
4. **Connect**
   - Guard: throw "already connecting" if `state == .connecting`.
   - On error: clear `quicClient` / `stream` / `reader` / `writer`, set `state = .error`, then `try? await w?.close()`.
5. **Plugin**
   - Disconnect existing client before creating a new one on `connect`.
   - `publish`: support `payload` as `string` or `number[]` (Uint8Array); reject otherwise.
   - `unsubscribe`: call `client.unsubscribe` instead of resolving without doing it.

### Android (MQTTClient.kt, MqttQuicPlugin.kt)

1. **Message loop**
   - Re-fetch `reader` from `lock` each iteration; `break` if `null`.
   - Re-fetch `writer` under lock when handling PINGREQ and PUBACK.
2. **Disconnect**
   - `job?.cancel()`, then `job?.join()` before clearing refs.
   - Use a local `writer` copy to send DISCONNECT and close.
3. **Packet ID**
   - `nextPacketIdUsed()` is `suspend` and uses `lock.withLock` for increment and wrap.
4. **Connect**
   - Guard: throw "already connecting" if `state == CONNECTING`.
   - On error: clear quic/stream/reader/writer, set `state = ERROR`, then `try { wr?.close() }`.
5. **Scope**
   - Use `CoroutineScope(Dispatchers.Default + SupervisorJob())` for the client.
6. **Plugin**
   - Disconnect existing client before creating a new one on `connect`.
   - `publish`: support `payload` as `string` or `number[]`; reject otherwise.

---

## P1 – High (Stability & Web)

### Web/PWA (src/web.ts)

- **New implementation** using `mqtt.js` over WebSocket:
  - `connect`: `ws://` or `wss://` (wss when port 8884 or 443), `connectTimeout` 30s, protocol 4/5, session properties.
  - `disconnect`: `end(false)`, clear client, remove listeners.
  - `publish` / `subscribe` / `unsubscribe`: forward to `mqtt` client with MQTT 5 props (messageExpiry, contentType, userProperties, subscriptionIdentifier, etc.).
- **Guards:** "already connecting" when a client exists but is not connected.
- **Dependency:** `mqtt` ^5.3.0 added to `package.json`.

### Client recreation (iOS & Android plugins)

- **Connect:** If client is already connected, call `disconnect()` (and await on iOS) before creating a new client and connecting.

### Error recovery & resource leaks

- **Connect failure (iOS):** Clear quic/stream/reader/writer, set error state, close writer (stream) before rethrowing.
- **Connect failure (Android):** Same cleanup + `writer?.close()` in `catch`.
- **Web:** `connectTimeout: 30_000` and proper `reject` on connect/error.

---

## Build

```bash
cd ref-code/capacitor-mqtt-quic
npm install   # installs mqtt
npm run build
```

## Testing

- **iOS:** Unit tests, plus manual connect/publish/subscribe/unsubscribe/disconnect and rapid connect/disconnect.
- **Android:** Same as iOS.
- **Web:** Run app in browser; use WSS broker; verify connect, publish, subscribe, unsubscribe, disconnect.
