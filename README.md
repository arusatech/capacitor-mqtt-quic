# @annadata/capacitor-mqtt-quic

MQTT-over-QUIC Capacitor plugin for **iOS**, **Android**, and **Web (browser/PWA)**. Native: ngtcp2 + WolfSSL for QUIC; Web: MQTT over WebSocket (WSS), same API and event listeners.

**Capacitor:** **8.0+** (tested with Capacitor 8).

**Features:**
- ✅ **MQTT 5.0** support with full properties and reason codes
- ✅ **MQTT 3.1.1** support (backward compatible)
- ✅ Automatic protocol negotiation (tries 5.0, falls back to 3.1.1)
- ✅ QUIC transport (ngtcp2) - currently using stubs (see ngtcp2 build section)
- ✅ Transport abstraction (StreamReader/StreamWriter)
- ✅ Full MQTT client API (connect, publish, subscribe, unsubscribe, disconnect)

## Structure

- **Phase 1**: MQTT protocol layer (Swift/Kotlin) - **Complete** ✅
  - MQTT 3.1.1 protocol implementation
  - MQTT 5.0 protocol implementation with properties and reason codes
  - Transport abstraction (StreamReader/StreamWriter)
- **Phase 2**: QUIC transport (ngtcp2) + stream adapters - **In Progress** ⏳
  - Currently uses stub implementations for testing
  - See [NGTCP2_INTEGRATION_PLAN.md](./docs/NGTCP2_INTEGRATION_PLAN.md) for build instructions
- **Phase 3**: MQTT client API + Capacitor plugin bridge - **Complete** ✅
- **Phase 4**: Platform integration in annadata-production - **Complete** ✅

## Plugin API

### Basic Usage (MQTT 3.1.1)

```ts
import { MqttQuic } from '@annadata/capacitor-mqtt-quic';

// Connect
await MqttQuic.connect({
  host: 'mqtt.example.com',
  port: 1884,
  clientId: 'my-client-id',
  username: 'user',
  password: 'pass',
  cleanSession: true,
  keepalive: 20
});

// Publish
await MqttQuic.publish({
  topic: 'sensors/temperature',
  payload: '25.5',
  qos: 1,
  retain: false
});

// Subscribe
await MqttQuic.subscribe({
  topic: 'sensors/+',
  qos: 1
});

// Unsubscribe
await MqttQuic.unsubscribe({ topic: 'sensors/+' });

// Disconnect
await MqttQuic.disconnect();
```

### Connection state and UI

`connect()` returns a Promise that resolves with `{ connected: true }` only after the QUIC handshake and MQTT CONNACK. To avoid the UI staying on "connecting":

- **Option A – use the Promise:** Set your UI to "connected" when the Promise resolves.

```ts
setConnectionState('connecting');
try {
  await MqttQuic.connect({ host, port, clientId, ... });
  setConnectionState('connected');  // required: update here
} catch (e) {
  setConnectionState('error');
}
```

- **Option B – use events:** The plugin also emits `connected` and `subscribed` (Capacitor listeners). You can rely on these instead of or in addition to the Promise:

```ts
import { MqttQuic } from '@annadata/capacitor-mqtt-quic';

MqttQuic.addListener('connected', () => setConnectionState('connected'));
MqttQuic.addListener('subscribed', (e) => { /* e.topic */ });
// then call connect(); state will update when the event fires
```

If you only set state to "connecting" and never handle the resolution or the `connected` event, the UI will remain "connecting" even though the connection succeeded.

### TLS Certificate Verification (QUIC)

QUIC requires TLS 1.3 and certificate verification is **enabled by default**.
You can bundle a CA PEM and it will be loaded automatically:

- iOS: `ios/Sources/MqttQuicPlugin/Resources/mqttquic_ca.pem`
- Android: `android/src/main/assets/mqttquic_ca.pem`

You can also override per call:

```ts
await MqttQuic.connect({
  host: 'mqtt.example.com',
  port: 1884,
  clientId: 'my-client-id',
  caFile: '/path/to/ca-bundle.pem',
  // or caPath: '/path/to/ca-directory'
});
```

#### How to generate certificates

**Option A: Public CA (Let’s Encrypt)**
You do not bundle `mqttquic_ca.pem` (the OS already trusts public CAs).

```bash
sudo apt-get update
sudo apt-get install -y certbot
sudo certbot certonly --standalone -d mqtt.example.com
```

Use on server:
- Cert: `/etc/letsencrypt/live/mqtt.example.com/fullchain.pem`
- Key: `/etc/letsencrypt/live/mqtt.example.com/privkey.pem`

**Option B: Private CA (dev/internal)**
Generate your own CA, sign the server cert, and bundle the CA PEM.

```bash
mkdir -p certs && cd certs

# 1) Create CA (one-time)
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.pem \
  -subj "/C=US/ST=CA/L=SF/O=Annadata/OU=MQTT/CN=Annadata-Root-CA"

# 2) Create server key + CSR
openssl genrsa -out server.key 2048
openssl req -new -key server.key -out server.csr \
  -subj "/C=US/ST=CA/L=SF/O=Annadata/OU=MQTT/CN=mqtt.example.com"

# 3) Add SANs (edit DNS/IP)
cat > server_ext.cnf <<EOF
subjectAltName = DNS:mqtt.example.com,IP:YOUR.SERVER.IP
extendedKeyUsage = serverAuth
EOF

# 4) Sign server cert
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca.key -CAcreateserial \
  -out server.pem -days 365 -sha256 -extfile server_ext.cnf
```

Bundle the CA cert (never ship `ca.key`):
- iOS: `ios/Sources/MqttQuicPlugin/Resources/mqttquic_ca.pem` (use `ca.pem`)
- Android: `android/src/main/assets/mqttquic_ca.pem` (use `ca.pem`)

### Test Harness (QUIC Smoke Test)

This runs: connect → subscribe → publish → disconnect.

```ts
await MqttQuic.testHarness({
  host: 'mqtt.example.com',
  port: 1884,
  clientId: 'mqttquic_test_client',
  topic: 'test/topic',
  payload: 'Hello QUIC!',
  // optional CA override
  caFile: '/path/to/ca-bundle.pem'
});
```

### MQTT 5.0 Features

#### Protocol Version Selection

```ts
// Use MQTT 5.0 explicitly
await MqttQuic.connect({
  host: 'mqtt.example.com',
  port: 1884,
  clientId: 'my-client-id',
  protocolVersion: '5.0',  // '3.1.1' | '5.0' | 'auto' (default)
  sessionExpiryInterval: 3600,  // Session persists 1 hour after disconnect
  keepalive: 20
});

// Auto-negotiation (default): tries 5.0, falls back to 3.1.1
await MqttQuic.connect({
  protocolVersion: 'auto',  // or omit
  // ...
});
```

#### Session Management

```ts
// Session expiry: control how long sessions persist after disconnect
await MqttQuic.connect({
  // ...
  protocolVersion: '5.0',
  sessionExpiryInterval: 3600,  // 1 hour in seconds
  // 0 = session expires immediately on disconnect
  // undefined/null = session expires on disconnect (default)
});
```

#### Message Expiry

```ts
// Messages auto-expire if not delivered within time limit
await MqttQuic.publish({
  topic: 'events/urgent',
  payload: 'Important message',
  messageExpiryInterval: 300,  // Expires in 5 minutes
  contentType: 'application/json'
});
```

#### Subscription Identifiers

```ts
// Identify which subscription triggered a message
await MqttQuic.subscribe({
  topic: 'sensors/+',
  qos: 1,
  subscriptionIdentifier: 1  // Unique ID for this subscription
});

// When message arrives, you'll know which subscription matched
```

#### User Properties (Custom Metadata)

```ts
// Add custom metadata to messages
await MqttQuic.publish({
  topic: 'events',
  payload: JSON.stringify({ value: 42 }),
  userProperties: [
    { name: 'source', value: 'mobile-app' },
    { name: 'version', value: '1.2.3' },
    { name: 'device-id', value: 'device-123' }
  ],
  contentType: 'application/json'
});
```

#### Response Topic & Correlation Data

```ts
// Request-response pattern
await MqttQuic.publish({
  topic: 'request/data',
  payload: 'request-id-123',
  responseTopic: 'response/data',  // Where to send response
  correlationData: 'correlation-id-456'  // Match request/response
});
```

## MQTT 5.0 Features Summary

| Feature | Description | Use Case |
|---------|-------------|----------|
| **Session Expiry** | Control session persistence | Resume sessions after reconnect |
| **Message Expiry** | Auto-expire undelivered messages | Time-sensitive data |
| **Subscription Identifiers** | Identify subscription source | Multi-subscription handling |
| **User Properties** | Custom key-value metadata | Tracing, versioning, routing |
| **Content Type** | Message format indicator | JSON, XML, binary, etc. |
| **Response Topic** | Request-response pattern | RPC over MQTT |
| **Reason Codes** | Detailed error information | Better debugging |
| **Topic Aliases** | Reduce bandwidth | High-frequency publishing |

See [MQTT5_IMPLEMENTATION_COMPLETE.md](./docs/MQTT5_IMPLEMENTATION_COMPLETE.md) for full details.

## TypeScript Interface

```ts
interface MqttQuicConnectOptions {
  host: string;
  port: number;
  clientId: string;
  username?: string;
  password?: string;
  cleanSession?: boolean;
  keepalive?: number;
  caFile?: string;
  caPath?: string;
  // MQTT 5.0 options
  protocolVersion?: '3.1.1' | '5.0' | 'auto';
  sessionExpiryInterval?: number;
  receiveMaximum?: number;
  maximumPacketSize?: number;
  topicAliasMaximum?: number;
}

interface MqttQuicPublishOptions {
  topic: string;
  payload: string | Uint8Array;
  qos?: 0 | 1 | 2;
  retain?: boolean;
  // MQTT 5.0 properties
  messageExpiryInterval?: number;
  contentType?: string;
  responseTopic?: string;
  correlationData?: string | Uint8Array;
  userProperties?: Array<{ name: string; value: string }>;
}

interface MqttQuicSubscribeOptions {
  topic: string;
  qos?: 0 | 1 | 2;
  // MQTT 5.0
  subscriptionIdentifier?: number;
}

interface MqttQuicTestHarnessOptions {
  host: string;
  port?: number;
  clientId?: string;
  topic?: string;
  payload?: string;
  caFile?: string;
  caPath?: string;
}
```

## ngtcp2 Build (Phase 2) ⏳

**Current Status:** Real QUIC transport implemented using ngtcp2 + **WolfSSL** on both iOS and Android (single TLS backend for license/size/QUIC support).

### Quick Build (Recommended)

Use the unified build script to build all native dependencies:

```bash
# Build for both iOS and Android
./build-native.sh

# Build only iOS
./build-native.sh --ios-only

# Build only Android
./build-native.sh --android-only

# Build for specific Android ABI
./build-native.sh --android-only --abi arm64-v8a
```

This script builds WolfSSL → nghttp3 → ngtcp2 in the correct order for both platforms (or OpenSSL/QuicTLS when USE_WOLFSSL=0).

### Manual Build

For detailed manual build instructions, see:
- **iOS**: [ios/NGTCP2_BUILD_INSTRUCTIONS.md](./ios/NGTCP2_BUILD_INSTRUCTIONS.md)
- **Android**: [android/NGTCP2_BUILD_INSTRUCTIONS.md](./android/NGTCP2_BUILD_INSTRUCTIONS.md)
- **Full Plan**: [NGTCP2_INTEGRATION_PLAN.md](./docs/NGTCP2_INTEGRATION_PLAN.md)

**Prerequisites:**
- iOS: macOS with Xcode 15+
- Android: Android Studio with NDK r25+ (auto-detected from `$ANDROID_HOME`)

## Production / First-time build

When you install the plugin from npm (`npm install @annadata/capacitor-mqtt-quic`), the published package **may** include **prebuilt native libs** (iOS and optionally Android, both using **WolfSSL**). If it does (a "complete" / zero-config package), you only need:

```bash
npm install @annadata/capacitor-mqtt-quic
npx cap sync
ionic cap run android   # or ios
```

**If your Android build fails with "WolfSSL not found"**, the package you installed does not include prebuilt Android libs. Do **one** of the following.

**Option A – One-time build (from your app project root, requires Android NDK r25+):** Both iOS and Android use **WolfSSL** as the TLS backend (license/size/QUIC support):

```bash
cd node_modules/@annadata/capacitor-mqtt-quic
./build-native.sh --android-only --abi arm64-v8a
./build-native.sh --android-only --abi armeabi-v7a
./build-native.sh --android-only --abi x86_64
```

Or from the plugin’s `android` directory:

```bash
cd node_modules/@annadata/capacitor-mqtt-quic/android
./build-wolfssl.sh --abi arm64-v8a
./build-wolfssl.sh --abi armeabi-v7a
./build-wolfssl.sh --abi x86_64
./build-nghttp3.sh --abi arm64-v8a
./build-nghttp3.sh --abi armeabi-v7a
./build-nghttp3.sh --abi x86_64
./build-ngtcp2.sh --abi arm64-v8a
./build-ngtcp2.sh --abi armeabi-v7a
./build-ngtcp2.sh --abi x86_64
```

Or add to your app’s `package.json` and run once:

```json
"setup:wolfssl-android": "cd node_modules/@annadata/capacitor-mqtt-quic && ./build-native.sh --android-only --abi arm64-v8a && ./build-native.sh --android-only --abi armeabi-v7a && ./build-native.sh --android-only --abi x86_64"
```

**Option B – Use a complete package:** Reinstall a version of the plugin that was published with Android prebuilts (see *Publishing a complete package* below). Then no one-time build is needed.

**iOS:** The plugin typically ships with vendored static libs (`ios/libs/`) using WolfSSL. If you built the plugin from source and those are missing, run from the plugin repo: `./build-native.sh --ios-only`, then pack/publish.

### Publishing a complete (zero-config) package

So that **clients have no native build step**, build Android (and iOS) prebuilts **before** publishing, then publish. The tarball will include `android/install/` and consumers can `npm install` and run the app without running `build-native.sh`.

From the **plugin repo** (capacitor-mqtt-quic), before `npm publish`:

```bash
# 1) Android prebuilts for all ABIs (required for zero-config Android)
npm run build:android-prebuilts

# 2) iOS prebuilts (if not already present)
./build-native.sh --ios-only

# 3) Build JS and publish (clean does not remove android/install or ios/libs)
npm run build
npm run clean:build-artifacts
npm version patch   # or minor
npm publish --access public
```

See **docs/PRODUCTION_PUBLISH_STEPS.md** for the full checklist.

### Connection error: `{"code":"UNIMPLEMENTED"}`

Capacitor returns this when the **native plugin method is not found** on the current platform. Common causes and fixes:

| Platform | Check |
|----------|--------|
| **iOS** | Plugin must be linked. Run `npx cap sync ios` and `cd ios && pod install`, then rebuild in Xcode. Ensure `@annadata/capacitor-mqtt-quic` is in your app’s `package.json` and that the iOS project includes the plugin (Capacitor should auto-discover it). If you use a custom Podfile, ensure the AnnadataCapacitorMqttQuic plugin target is included. |
| **Android** | Run `npx cap sync android` and rebuild. If you see "WolfSSL not found", run the one-time native build (see above). |
| **Web / browser** | In browser, the plugin uses the **web** implementation (WSS or WebTransport). If you get UNIMPLEMENTED in the browser, the app may be resolving the native bridge instead of the web plugin—e.g. wrong `capacitor.config` or build. Ensure you’re opening the app as a web build (e.g. `ionic serve` or `cap run web`), not a native app with a WebView. |

After adding the plugin or changing native code, always run **`npx cap sync`** and on iOS **`pod install`**, then rebuild the native app.

## Development

### Build Plugin

```bash
git clone https://github.com/annadata/capacitor-mqtt-quic.git
cd capacitor-mqtt-quic
npm install
npm run build
```

### Add to Capacitor App

```bash
cd your-capacitor-app
npm install @annadata/capacitor-mqtt-quic
npx cap sync
```

### Usage in App

```ts
import { MqttQuic } from '@annadata/capacitor-mqtt-quic';
import { MqttQuicService } from './services/MqttQuicService';

// Via service (recommended)
const mqttService = new MqttQuicService();
await mqttService.connect();

// Or directly
await MqttQuic.connect({
  host: 'mqtt.annadata.cloud',
  port: 1884,
  clientId: 'device-123',
  protocolVersion: '5.0'
});
```

## Publishing (maintainers)

To pack the plugin **with native libs** and publish to npm, follow **[PRODUCTION_PUBLISH_STEPS.md](./docs/PRODUCTION_PUBLISH_STEPS.md)**.

## Documentation

- [Implementation Summary](./docs/IMPLEMENTATION_SUMMARY.md) - Complete project overview
- [MQTT 5.0 Implementation](./docs/MQTT5_IMPLEMENTATION_COMPLETE.md) - MQTT 5.0 features and usage
- [ngtcp2 Integration Plan](./docs/NGTCP2_INTEGRATION_PLAN.md) - Build instructions for real QUIC
- [MQTT Version Analysis](./docs/MQTT_VERSION_ANALYSIS.md) - Why MQTT 5.0?

## Web / browser support

The plugin runs in **browsers** (including PWA and `cap run web`) with the **same API** as iOS and Android.

**Why web can’t use ngtcp2 + WolfSSL:** Browsers do not expose raw UDP or the TLS APIs ngtcp2/WolfSSL need. So the native stack cannot run in the browser. On web: (1) **Default:** MQTT over **WebSocket (WSS)** via `mqtt.js`. (2) **Optional:** MQTT over **WebTransport** (QUIC)—pass `webTransportUrl` in `connect()` when your server supports WebTransport; the browser uses its built-in HTTP/3/QUIC stack.

- **Connect:** `ws://host:port` or `wss://host:port` (the plugin uses WSS when port is 8884 or 443, otherwise `ws`)
- **Same methods:** `MqttQuic.connect`, `publish`, `subscribe`, `unsubscribe`, `disconnect`, `testHarness`

**My MQTT+QUIC server is on port 1884 – can WSS connect?**  
Port **1884** is usually **MQTT over QUIC** (UDP). A **WSS client cannot connect directly to 1884**, because WSS is TCP/WebSocket and 1884 is QUIC. You need one of:

1. **Server also exposes MQTT over WebSocket**  
   Many brokers listen on two ports: e.g. **1884** for MQTT-over-QUIC and **8884** (or 8084) for MQTT-over-WebSocket Secure. From the **web** plugin, connect to the **WebSocket port** (e.g. 8884), not 1884:
   ```ts
   await MqttQuic.connect({ host: 'your-server.com', port: 8884, clientId: 'web-client' });
   ```
   The plugin will use `wss://your-server.com:8884`.

2. **Proxy/gateway**  
   Run a gateway that listens for WSS (e.g. on 8884) and forwards MQTT to your QUIC server on 1884. The web client then connects to the gateway’s WSS port.

3. **Native or WebTransport**  
   On **iOS/Android** use the same host and **port 1884** (QUIC). On **web**, if the server supports **WebTransport**, use `webTransportUrl` (see example below) so the browser uses QUIC via WebTransport.
- **Same events:** `MqttQuic.addListener('connected', ...)`, `addListener('subscribed', ...)`, `addListener('message', (e) => { e.topic, e.payload })`
- **Build:** The plugin bundles `mqtt`; no extra install in the app.

Example in a browser or PWA:

```ts
import { MqttQuic } from '@annadata/capacitor-mqtt-quic';

MqttQuic.addListener('message', (e) => console.log(e.topic, e.payload));
await MqttQuic.connect({ host: 'broker.example.com', port: 8884, clientId: 'web-client' });
await MqttQuic.subscribe({ topic: 'sensors/#' });
```

Example with QUIC on web (WebTransport; server must support WebTransport and MQTT over it):

```ts
await MqttQuic.connect({
  webTransportUrl: 'https://broker.example.com:443/mqtt-wt',
  clientId: 'web-quic-client',
  host: 'broker.example.com',
  port: 443,
});
```

When the server uses path-based routing (like MQTT topics), data is at `.../devices/<deviceId>/<action>/<Path>`. You can pass the base URL and path components; the plugin builds the full URL:

```ts
await MqttQuic.connect({
  webTransportUrl: 'https://mqtt.annadata.cloud:443/mqtt-wt',
  webTransportDeviceId: 'mydevice',
  webTransportAction: 'subscribe',   // or 'publish', etc.
  webTransportPath: 'sensors/temp',   // optional; like MQTT topic suffix
  clientId: 'web-client',
  host: 'mqtt.annadata.cloud',
  port: 443,
});
// Connects to: https://mqtt.annadata.cloud:443/mqtt-wt/devices/mydevice/subscribe/sensors/temp
```

## Compatibility

- **Platforms:** **iOS**, **Android**, **Web (browser / PWA)**
- **MQTT Protocol:** 3.1.1 and 5.0 (auto-negotiation)
- **iOS:** 15.0+
- **Android:** API 21+ (Android 5.0+)
- **Web:** Any modern browser; MQTT over WSS
- **Capacitor:** 8.0+
- **QUIC:** ngtcp2 + WolfSSL on native; on web, optional WebTransport (browser's HTTP/3/QUIC) when server supports it

## Author

**Yakub Mohammad**

- yakub@annadata.ai
- yakub@arusatech.com
- yakub@arusallc.com

## License

MIT
