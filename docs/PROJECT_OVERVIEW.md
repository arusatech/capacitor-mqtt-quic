# @annadata/capacitor-mqtt-quic — Complete Project Overview

This document explains the **entire project**: what it is, how it’s built, and how the pieces fit together.

---

## 1. What This Project Is

**@annadata/capacitor-mqtt-quic** is a **Capacitor plugin** that lets mobile and web apps talk **MQTT** (publish/subscribe messaging) over different transports:

| Platform   | Transport              | Technology                          |
|------------|------------------------|-------------------------------------|
| **iOS**    | MQTT over **QUIC**     | ngtcp2 + WolfSSL (native C/C++/Swift) |
| **Android**| MQTT over **QUIC**     | ngtcp2 + WolfSSL (native C++/Kotlin JNI) |
| **Web**    | MQTT over **WebSocket** (default) | mqtt.js (WSS)                    |
| **Web**    | MQTT over **WebTransport** (optional) | Browser’s HTTP/3/QUIC + mqtt-packet |

Your app uses **one API** in JavaScript/TypeScript (`MqttQuic.connect`, `publish`, `subscribe`, etc.); the plugin picks the right implementation per platform.

---

## 2. Why MQTT + QUIC?

- **MQTT**: Lightweight pub/sub protocol (topics, QoS, retain). Common in IoT and real-time apps.
- **QUIC**: Modern transport (UDP + TLS 1.3). Faster handshake, better on bad networks, multiplexing.
- **MQTT over QUIC**: Run MQTT on top of QUIC instead of TCP. Your server (e.g. mqtt.annadata.cloud:1884) speaks MQTT-over-QUIC; this plugin is the client for Capacitor apps.

Browsers can’t use raw QUIC, so on **web** the plugin uses **WebSocket (WSS)** or, optionally, **WebTransport** (browser’s QUIC) when the server supports it.

---

## 3. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Your Capacitor App (JavaScript/TypeScript)                      │
│  import { MqttQuic } from '@annadata/capacitor-mqtt-quic';       │
│  await MqttQuic.connect({ host, port: 1884, clientId });        │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│  Capacitor bridge (src/index.ts)                                 │
│  registerPlugin('MqttQuic', { web: () => MqttQuicWeb });          │
│  → On iOS/Android: calls native plugin                            │
│  → On Web: uses MqttQuicWeb (src/web.ts)                         │
└──────┬─────────────────────────────────────────────┬────────────┘
       │                                               │
       ▼                                               ▼
┌──────────────────────┐                   ┌──────────────────────┐
│  iOS (Swift)          │                   │  Android (Kotlin)     │
│  MqttQuicPlugin       │                   │  MqttQuicPlugin       │
│  → MQTTClient         │                   │  → MQTTClient         │
│  → NGTCP2Client       │                   │  → NGTCP2Client (JNI) │
│  → NGTCP2Bridge (C++) │                   │  → ngtcp2_jni.cpp     │
│  → ngtcp2 + WolfSSL   │                   │  → ngtcp2 + WolfSSL   │
└──────────────────────┘                   └──────────────────────┘
       │                                               │
       └───────────────────────┬───────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │  MQTT+QUIC server    │
                    │  e.g. :1884          │
                    └──────────────────────┘
```

---

## 4. Repository Structure (What Lives Where)

### 4.1 JavaScript/TypeScript (shared API and web)

| Path | Purpose |
|------|--------|
| **src/index.ts** | Registers the plugin with Capacitor; exports `MqttQuic` and types. On native, Capacitor routes to iOS/Android; on web, uses the web implementation. |
| **src/definitions.ts** | TypeScript interfaces: `MqttQuicConnectOptions`, `MqttQuicPublishOptions`, `MqttQuicSubscribeOptions`, plugin interface, and WebTransport path options (`webTransportUrl`, `webTransportDeviceId`, etc.). |
| **src/web.ts** | Web implementation: `MqttQuicWeb` extends `WebPlugin`. Uses **mqtt.js** for WSS; optionally **WebTransport** + **mqtt-packet** when `webTransportUrl` is set. Same methods and events as native. |
| **dist/** | Built output (from `npm run build`): ESM, CJS, and bundled `plugin.js` for the app. |

### 4.2 iOS (native)

| Path | Purpose |
|------|--------|
| **ios/Sources/MqttQuicPlugin/MqttQuicPlugin.swift** | Capacitor plugin entry: declares methods (connect, publish, subscribe, …), reads options from JS, calls `MQTTClient` and `NGTCP2Client`, and notifies listeners (`connected`, `subscribed`, `message`). |
| **ios/Sources/.../Client/MQTTClient.swift** | MQTT protocol state machine: CONNECT, PUBLISH, SUBSCRIBE, UNSUBSCRIBE, DISCONNECT; uses a transport (stream read/write). |
| **ios/Sources/.../MQTT/** | MQTT 3.1.1 and 5.0 parsing/serialization (types, reason codes, properties). |
| **ios/Sources/.../QUIC/NGTCP2Client.swift** | Swift wrapper around the C++ QUIC client. |
| **ios/Sources/.../QUIC/NGTCP2Bridge.mm** | C++ bridge to **ngtcp2** and **WolfSSL**: socket, TLS, QUIC handshake, streams; used by `NGTCP2Client`. |
| **ios/Sources/.../Transport/** | Transport abstraction (stream reader/writer) and QUIC stream adapter. |
| **ios/libs/** | Prebuilt static libs: `libngtcp2.a`, `libngtcp2_crypto_wolfssl.a`, `libnghttp3.a`, `libwolfssl.a` (shipped in the npm package for CocoaPods). |
| **ios/include/** | Headers for ngtcp2/nghttp3/wolfssl. |
| **AnnadataCapacitorMqttQuic.podspec** | CocoaPods spec: name, version, source files, vendored libs, link flags. |

### 4.3 Android (native)

| Path | Purpose |
|------|--------|
| **android/.../MqttQuicPlugin.kt** | Capacitor plugin: `@CapacitorPlugin`, methods (connect, publish, subscribe, …), calls `MQTTClient` and `NGTCP2Client`, notifies listeners. |
| **android/.../client/MQTTClient.kt** | MQTT client logic (same role as iOS `MQTTClient`). |
| **android/.../mqtt/** | MQTT 3.1.1 and 5.0 (types, protocol, properties). |
| **android/.../quic/NGTCP2Client.kt** | Kotlin API for the native QUIC client. |
| **android/.../cpp/ngtcp2_jni.cpp** | JNI layer: connects to ngtcp2 + **WolfSSL** (same TLS stack as iOS), implements QUIC + MQTT stream. |
| **android/.../cpp/CMakeLists.txt** | CMake: builds the native `.so`, links WolfSSL and ngtcp2 (from `android/install/` after you run the build scripts). |
| **android/install/** | After building: `wolfssl-android/<abi>/`, `ngtcp2-android/<abi>/`, `nghttp3-android/<abi>/`. Can be shipped in the package for zero-config. |

### 4.4 Build and publish

| Path | Purpose |
|------|--------|
| **build-native.sh** | One script to build native deps: WolfSSL → nghttp3 → ngtcp2 for iOS and/or Android (per ABI). |
| **deps-versions.sh** | Pinned versions/commits for WolfSSL, ngtcp2, nghttp3; sourced by build scripts. |
| **ios/build-wolfssl.sh**, **android/build-wolfssl.sh** | Build WolfSSL for iOS/Android. |
| **ios/build-ngtcp2.sh**, **android/build-ngtcp2.sh** | Build ngtcp2 (with WolfSSL). |
| **package.json** | Plugin name, version, `files`, `capacitor.ios/android/web`, scripts (`build`, `clean:build-artifacts`, `prepublishOnly`). |
| **PRODUCTION_PUBLISH_STEPS.md** | Checklist: build native libs, clean, build JS, version, publish. |
| **.npmignore** | Excludes build junk but keeps `ios/libs`, `ios/include`, and (if present) `android/install` so the package is self-contained. |

---

## 5. Data Flow (Example: Connect and Publish)

1. **App** calls `MqttQuic.connect({ host: 'mqtt.annadata.cloud', port: 1884, clientId: 'x' })`.
2. **Capacitor** invokes the native plugin (iOS/Android) or the web implementation.
3. **Native (e.g. Android)**  
   - `MqttQuicPlugin.connect()` parses options, sets CA env if needed.  
   - Calls `NGTCP2Client` (JNI) to open a QUIC connection to host:1884.  
   - `ngtcp2_jni.cpp` uses WolfSSL for TLS and ngtcp2 for QUIC, then runs MQTT over the QUIC stream.  
   - `MQTTClient` sends CONNECT, gets CONNACK, then plugin calls `notifyListeners("connected", …)`.  
4. **Web**  
   - If no `webTransportUrl`: `mqtt.js` connects to `wss://host:8884` (or `ws://host:port`).  
   - If `webTransportUrl` is set: open WebTransport, create one bidirectional stream, send MQTT CONNECT with mqtt-packet, wait for CONNACK, then notify `connected`.  
5. **Publish**  
   - App calls `MqttQuic.publish({ topic, payload })`.  
   - Same bridge: native side uses `MQTTClient.publish` over the QUIC stream; web uses mqtt.js or mqtt-packet over WSS/WebTransport.  
   - Incoming PUBLISH is delivered via `notifyListeners('message', { topic, payload })` (native) or `this.notifyListeners('message', …)` (web).

So: **one API**, different transport per platform; events and method names are the same everywhere.

---

## 6. Web Behaviour in Detail

- **Default (no WebTransport)**  
  `webTransportUrl` not set → `MqttQuicWeb` uses **mqtt.js** and connects to `ws://host:port` or `wss://host:port` (WSS when port is 8884 or 443). Same `connect`/`publish`/`subscribe`/`unsubscribe`/`disconnect` and `addListener('connected'|'subscribed'|'message')`.

- **With WebTransport**  
  `webTransportUrl` set (and optionally `webTransportDeviceId`, `webTransportAction`, `webTransportPath`) → plugin builds URL like `https://host:443/mqtt-wt/devices/<deviceId>/<action>/<path>`, opens WebTransport, runs MQTT over one bidirectional stream using **mqtt-packet**. Browser uses HTTP/3/QUIC; server must support WebTransport and MQTT on that path.

- Browsers **cannot** use the same native ngtcp2+WolfSSL stack (no UDP); so “QUIC on web” is only via WebTransport when the server supports it.

---

## 7. TLS and Certificates

- **Native (iOS/Android)**  
  QUIC uses TLS 1.3 (WolfSSL). CA can be: bundled PEM in the app (e.g. `mqttquic_ca.pem`), or `caFile`/`caPath` passed in `connect()`. Env vars `MQTT_QUIC_CA_FILE` / `MQTT_QUIC_CA_PATH` are used by the native layer.

- **Web (WSS)**  
  Certificate verification is done by the browser for the WebSocket connection.

- **Web (WebTransport)**  
  Same: HTTPS origin and server certificate are validated by the browser.

---

## 8. Build and Publish Summary

- **JS/Web**  
  `npm run build` → TypeScript compile + Rollup bundle → `dist/`. No native steps needed for web-only.

- **iOS**  
  Build native libs (WolfSSL, nghttp3, ngtcp2) with `./build-native.sh --ios-only` so `ios/libs/` and `ios/include/` exist. Podspec references these; `pod install` in the app links them.

- **Android**  
  Build WolfSSL + nghttp3 + ngtcp2 per ABI (e.g. `./build-native.sh --android-only --abi arm64-v8a`) so `android/install/` is populated. App’s CMake then finds them when building the plugin’s `.so`.

- **Publish**  
  See **PRODUCTION_PUBLISH_STEPS.md**: build native (if shipping prebuilts), `npm run clean:build-artifacts`, `npm run build`, bump version, `npm publish --access public`. The `files` in package.json and `.npmignore` control what gets into the tarball (e.g. `dist`, `ios`, `android`, `deps-versions.sh`, `build-native.sh`, and optionally prebuilt `ios/libs`, `android/install`).

---

## 9. Summary Table

| Layer | iOS | Android | Web |
|-------|-----|---------|-----|
| **Plugin entry** | MqttQuicPlugin.swift | MqttQuicPlugin.kt | MqttQuicWeb (web.ts) |
| **MQTT** | MQTTClient + MQTT/*.swift | MQTTClient + mqtt/*.kt | mqtt.js or mqtt-packet |
| **Transport** | QUIC (ngtcp2) | QUIC (ngtcp2 via JNI) | WSS or WebTransport |
| **TLS/QUIC libs** | WolfSSL + ngtcp2 (vendored .a) | WolfSSL + ngtcp2 (install/) | Browser / mqtt.js |
| **Same API** | Yes | Yes | Yes |

This is the complete picture of the project: a single Capacitor plugin that provides MQTT over QUIC on native and MQTT over WSS (or WebTransport) on web, with one consistent API and event model.
