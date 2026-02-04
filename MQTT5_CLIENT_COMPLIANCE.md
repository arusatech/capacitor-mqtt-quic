# MQTT v5.0 Client Compliance Checklist

This document describes how the Capacitor MQTT-over-QUIC plugin aligns with the **OASIS MQTT v5.0** specification and interoperability with the **mqttd** server.

- **Specification:** [OASIS MQTT v5.0](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html)
- **Server compliance:** See [ref-code/mqttd/docs/MQTT5_SPEC_COMPLIANCE.md](../mqttd/docs/MQTT5_SPEC_COMPLIANCE.md) in the mqttd repo.

## Implemented (required for spec and mqttd)

| Area | Spec reference | Status | Notes |
|------|----------------|--------|-------|
| **§3.1 CONNECT** | Protocol name "MQTT", version 5; Connect Flags (reserved bit 0); CONNECT properties | ✅ | Reserved bit 0 explicitly masked to 0 (`flags & 0xFE`). No Will in CONNECT yet (optional). |
| **§3.2 CONNACK** | Session Present, Reason Code, CONNACK properties | ✅ | **Server Keep Alive** (0x13) and **Assigned Client Identifier** (0x12) are read and applied; effective keepalive and client ID used for the session. |
| **§3.3 PUBLISH** | V5 variable header and payload parsing; Topic Alias | ✅ | `parsePublishV5` in Android/iOS; Topic Alias resolved when topic length is 0; map updated when topic + alias present. |
| **§3.8–3.9 SUBSCRIBE/SUBACK** | Subscription Options (at least QoS); reserved bits 6–7 = 0 | ✅ | Single topic per SUBSCRIBE; options byte masked with `0x3F` so reserved bits 6–7 are always 0 [MQTT-3.8.3-5]. |
| **§3.14 DISCONNECT** | Handle server DISCONNECT | ✅ | Message loop handles DISCONNECT (0xE0); connection closed, state updated, loop exits. |
| **§4.3.3 QoS 2 receive** | PUBREC → PUBREL → PUBCOMP | ✅ | Incoming QoS 2 PUBLISH: send PUBREC; on PUBREL send PUBCOMP. |
| **§4.12 AUTH** | Connect loop until CONNACK | ✅ | After CONNECT, loop until CONNACK; if **AUTH** (packet type 15, 0xF0) received, client sends DISCONNECT (Bad authentication method) and closes—enhanced auth not supported. |

## Packet type AUTH

- **Spec:** AUTH is packet type **15**; fixed header first byte = `0xF0` (15 << 4).
- **Android:** `MQTTTypes.kt` — `MQTTMessageType.AUTH: Byte = 0xF0`.
- **iOS:** `MQTTTypes.swift` — `MQTTMessageType.AUTH = 0xF0`.

Both platforms use this value in the connect loop to detect AUTH and fail cleanly when the server uses enhanced authentication.

## Optional (not required for basic compliance)

| Feature | Spec | Status | Notes |
|---------|------|--------|-------|
| **Subscription Options** | §3.8.3.1 No Local, Retain As Published, Retain Handling (0/1/2); reserved bits 6–7 = 0 | Optional | Currently only QoS (bits 0–1) sent; other options could be added to the API. |
| **Multiple topic filters in one SUBSCRIBE** | §3.8 | Optional | One topic per SUBSCRIBE today; API could accept multiple filters + options. |
| **Will message** | §3.1.2.5 Will Flag, Will Properties, Will Topic, Will Payload | Optional | CONNECT sends no Will; could add connect options for Will (topic, payload, QoS, retain, Will Delay Interval). |
| **Flow control (Receive Maximum)** | §4.9 | Optional | Client can send Receive Maximum in CONNECT and read CONNACK; no enforcement of send quota for QoS 1/2 PUBLISH yet (could block when quota 0). |

## Files (summary)

| Area | Android (Kotlin) | iOS (Swift) |
|------|------------------|-------------|
| CONNACK props | `MQTTClient.kt` (connect path) | `MQTTClient.swift` (connect path) |
| AUTH / connect loop | `MQTTClient.kt` | `MQTTClient.swift` |
| Packet type AUTH | `MQTTTypes.kt` (AUTH = 0xF0) | `MQTTTypes.swift` (AUTH = 0xF0) |
| DISCONNECT in loop | `MQTTClient.kt` (startMessageLoop) | `MQTTClient.swift` (startMessageLoop) |
| parsePublishV5 + Topic Alias | `MQTT5Protocol.kt`, `MQTTClient.kt` | `MQTT5Protocol.swift`, `MQTTClient.swift` |
| QoS 2 receive (PUBREC/PUBREL/PUBCOMP) | `MQTTProtocol.kt`, `MQTTClient.kt` | `MQTTProtocol.swift`, `MQTTClient.swift` |

No changes to the mqttd server are required; the plugin is aligned with the server and the MQTT v5.0 spec for the implemented features above.
