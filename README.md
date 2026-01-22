# @annadata/capacitor-mqtt-quic

MQTT-over-QUIC Capacitor plugin for iOS and Android. Uses ngtcp2 for QUIC on native; MQTT over WebSocket (WSS) fallback on web.

## Structure

- **Phase 1**: MQTT protocol layer (Swift/Kotlin) + transport abstraction (StreamReader/StreamWriter).
- **Phase 2**: QUIC transport (ngtcp2) + stream adapters. Currently uses stub implementations; see below for ngtcp2.
- **Phase 3**: MQTT client API (connect, publish, subscribe, disconnect) + Capacitor JS bridge.
- **Phase 4**: Platform integration in annadata-production (endpoints, MqttQuicService, auth).

## Plugin API

```ts
import { MqttQuic } from '@annadata/capacitor-mqtt-quic';

await MqttQuic.connect({ host, port, clientId, username?, password?, cleanSession?, keepalive? });
await MqttQuic.disconnect();
await MqttQuic.publish({ topic, payload, qos?, retain? });
await MqttQuic.subscribe({ topic, qos? });
await MqttQuic.unsubscribe({ topic });
```

## ngtcp2 build (Phase 2)

To enable real QUIC (replace stub):

1. **iOS**: Build ngtcp2 + OpenSSL/BoringSSL as static libs; add to Xcode. Use CMake with an iOS toolchain or vendored source. Pin ngtcp2 ≥ 1.21.
2. **Android**: Build ngtcp2 with NDK (CMake), produce `libngtcp2_client.so`. Link same TLS lib. See `android/quic/` for JNI wrapper layout.

UDP: iOS `NWConnection`, Android `DatagramSocket`. TLS 1.3 is required for QUIC.

## Development

```bash
npm install
npm run build
```

Add to your Capacitor app:

```bash
npm i @annadata/capacitor-mqtt-quic
npx cap sync
```

## License

MIT
