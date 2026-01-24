# @annadata/capacitor-mqtt-quic

MQTT-over-QUIC Capacitor plugin for iOS and Android. Uses ngtcp2 for QUIC on native; MQTT over WebSocket (WSS) fallback on web.

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
  - See [NGTCP2_INTEGRATION_PLAN.md](./NGTCP2_INTEGRATION_PLAN.md) for build instructions
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
  keepalive: 60
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
  keepalive: 60
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

See [MQTT5_IMPLEMENTATION_COMPLETE.md](./MQTT5_IMPLEMENTATION_COMPLETE.md) for full details.

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

**Current Status:** Real QUIC transport implemented using ngtcp2 + quictls (OpenSSL fork).

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

This script builds OpenSSL (quictls) → nghttp3 → ngtcp2 in the correct order for both platforms.

### Manual Build

For detailed manual build instructions, see:
- **iOS**: [ios/NGTCP2_BUILD_INSTRUCTIONS.md](./ios/NGTCP2_BUILD_INSTRUCTIONS.md)
- **Android**: [android/NGTCP2_BUILD_INSTRUCTIONS.md](./android/NGTCP2_BUILD_INSTRUCTIONS.md)
- **Full Plan**: [NGTCP2_INTEGRATION_PLAN.md](./NGTCP2_INTEGRATION_PLAN.md)

**Prerequisites:**
- iOS: macOS with Xcode 14+
- Android: Android Studio with NDK r25+ (auto-detected from `$ANDROID_HOME`)

## Development

### Build Plugin

```bash
cd production/capacitor-mqtt-quic
npm install
npm run build
```

### Add to Capacitor App

```bash
cd production/annadata-production
npm i @annadata/capacitor-mqtt-quic
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

## Documentation

- [Implementation Summary](./IMPLEMENTATION_SUMMARY.md) - Complete project overview
- [MQTT 5.0 Implementation](./MQTT5_IMPLEMENTATION_COMPLETE.md) - MQTT 5.0 features and usage
- [ngtcp2 Integration Plan](./NGTCP2_INTEGRATION_PLAN.md) - Build instructions for real QUIC
- [MQTT Version Analysis](./MQTT_VERSION_ANALYSIS.md) - Why MQTT 5.0?

## Web/PWA Support

On **web** (including PWA), the plugin uses **MQTT over WebSocket (WSS)** via `mqtt.js`. No QUIC; same API.

- **Connect:** `ws://host:port` or `wss://host:port` (wss when port is 8884 or 443)
- **Build:** Ensure `mqtt` is installed (`npm install` in the plugin directory)
- Use `MqttQuic.connect` / `publish` / `subscribe` / `unsubscribe` / `disconnect` as on native

## Compatibility

- **MQTT Protocol:** 3.1.1 and 5.0 (auto-negotiation)
- **iOS:** 15.0+ (for Network framework)
- **Android:** API 21+ (Android 5.0+)
- **Web/PWA:** mqtt.js over WSS
- **Capacitor:** 7.0+
- **QUIC:** ngtcp2 1.21.0+ (when integrated)

## License

MIT
