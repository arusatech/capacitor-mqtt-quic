//
// MqttQuicPlugin.swift
// MqttQuicPlugin
//
// Capacitor plugin bridge. Phase 3: connect/publish/subscribe call into MQTTClient.
//

import Foundation
import Capacitor

@objc(MqttQuicPlugin)
public class MqttQuicPlugin: CAPPlugin, CAPBridgedPlugin {

    public let identifier = "MqttQuicPlugin"
    public let jsName = "MqttQuic"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "ping", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "sendKeepalive", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "publish", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "subscribe", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "unsubscribe", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "testHarness", returnType: CAPPluginReturnPromise)
    ]

    private var client = MQTTClient(protocolVersion: .auto)

    @objc override public func load() {}

    @objc func sendKeepalive(_ call: CAPPluginCall) {
        let timeoutMs = UInt64(call.getInt("timeoutMs") ?? 5000)
        let clamped = min(max(timeoutMs, 1000), 15000)
        Task {
            do {
                let ok = await client.sendMqttPing(timeoutMs: clamped)
                DispatchQueue.main.async { call.resolve(["ok": ok]) }
            } catch {
                DispatchQueue.main.async { call.reject("\(error)") }
            }
        }
    }

    @objc func ping(_ call: CAPPluginCall) {
        let host = call.getString("host") ?? ""
        let port = call.getInt("port") ?? 1884
        guard !host.isEmpty else {
            call.reject("host is required")
            return
        }
        if NGTCP2Client.ping(host: host, port: UInt16(port)) {
            call.resolve(["ok": true])
        } else {
            call.reject("Server unreachable (UDP ping to \(host):\(port) failed)")
        }
    }

    private func bundledCaPath() -> String? {
        // Prefer app bundle so TLS works when installed from npm pack (pod resources may be in separate .bundle)
        if let mainPath = Bundle.main.path(forResource: "mqttquic_ca", ofType: "pem"),
           let mainContents = try? String(contentsOfFile: mainPath),
           mainContents.contains("BEGIN CERTIFICATE") {
            return mainPath
        }
        let bundle = Bundle(for: MqttQuicPlugin.self)
        guard let path = bundle.path(forResource: "mqttquic_ca", ofType: "pem") else {
            return nil
        }
        if let contents = try? String(contentsOfFile: path),
           contents.contains("BEGIN CERTIFICATE") {
            return path
        }
        return nil
    }

    @objc func connect(_ call: CAPPluginCall) {
        let host = call.getString("host") ?? ""
        let port = call.getInt("port") ?? 1884
        let clientId = call.getString("clientId") ?? ""
        let username = call.getString("username")
        let password = call.getString("password")
        let cleanSession = call.getBool("cleanSession") ?? true
        let keepalive = call.getInt("keepalive") ?? 20
        let protocolVersionStr = call.getString("protocolVersion") ?? "auto"
        let sessionExpiryInterval = call.getInt("sessionExpiryInterval")
        let caFile = call.getString("caFile")
        let caPath = call.getString("caPath")
        
        let protocolVersion: MQTTClient.ProtocolVersion
        switch protocolVersionStr {
        case "5.0": protocolVersion = .v5
        case "3.1.1": protocolVersion = .v311
        default: protocolVersion = .auto
        }

        guard !host.isEmpty, !clientId.isEmpty else {
            call.reject("host and clientId are required")
            return
        }

        Task {
            do {
                if let caFile = caFile {
                    setenv("MQTT_QUIC_CA_FILE", caFile, 1)
                } else if let bundled = bundledCaPath() {
                    setenv("MQTT_QUIC_CA_FILE", bundled, 1)
                } else {
                    unsetenv("MQTT_QUIC_CA_FILE")
                }
                if let caPath = caPath {
                    setenv("MQTT_QUIC_CA_PATH", caPath, 1)
                } else {
                    unsetenv("MQTT_QUIC_CA_PATH")
                }
                if !NGTCP2Client.ping(host: host, port: UInt16(port)) {
                    DispatchQueue.main.async { call.reject("Server unreachable (UDP ping to \(host):\(port) failed). Check network and firewall.") }
                    return
                }
                // Idempotent / prevent concurrent connect: avoid second call disconnecting or replacing client (server sees stream reset)
                switch client.getState() {
                case .connected:
                    DispatchQueue.main.async {
                        call.resolve(["connected": true])
                        self.notifyListeners("connected", data: ["connected": true])
                    }
                    return
                case .connecting:
                    DispatchQueue.main.async { call.reject("Already connecting") }
                    return
                case .disconnected, .error:
                    break
                }
                client = MQTTClient(protocolVersion: protocolVersion)
                // Forward every incoming PUBLISH to JS so addListener('message', ...) receives topic + payload (matches Android)
                client.onPublish = { [weak self] topic, payload in
                    guard let self = self else { return }
                    let payloadStr: String = {
                        if let str = String(data: payload, encoding: .utf8) { return str }
                        return payload.base64EncodedString()
                    }()
                    DispatchQueue.main.async {
                        self.notifyListeners("message", data: ["topic": topic as String, "payload": payloadStr as String])
                    }
                }
                try await client.connect(
                    host: host,
                    port: UInt16(port),
                    clientId: clientId,
                    username: username,
                    password: password,
                    cleanSession: cleanSession,
                    keepalive: UInt16(keepalive),
                    sessionExpiryInterval: sessionExpiryInterval != nil ? UInt32(sessionExpiryInterval!) : nil
                )
                DispatchQueue.main.async {
                    call.resolve(["connected": true])
                    self.notifyListeners("connected", data: ["connected": true])
                }
            } catch {
                DispatchQueue.main.async { call.reject("\(error)") }
            }
        }
    }

    @objc func testHarness(_ call: CAPPluginCall) {
        let host = call.getString("host") ?? ""
        let port = call.getInt("port") ?? 1884
        let clientId = call.getString("clientId") ?? "AcharyaAnnadata"
        let topic = call.getString("topic") ?? "test/topic"
        let payload = call.getString("payload") ?? "Hello QUIC!"
        let caFile = call.getString("caFile")
        let caPath = call.getString("caPath")

        if host.isEmpty {
            call.reject("host is required")
            return
        }

        Task {
            do {
                if let caFile = caFile {
                    setenv("MQTT_QUIC_CA_FILE", caFile, 1)
                } else if let bundled = bundledCaPath() {
                    setenv("MQTT_QUIC_CA_FILE", bundled, 1)
                } else {
                    unsetenv("MQTT_QUIC_CA_FILE")
                }
                if let caPath = caPath {
                    setenv("MQTT_QUIC_CA_PATH", caPath, 1)
                } else {
                    unsetenv("MQTT_QUIC_CA_PATH")
                }

                client = MQTTClient(protocolVersion: .auto)
                try await client.connect(
                    host: host,
                    port: UInt16(port),
                    clientId: clientId,
                    username: nil,
                    password: nil,
                    cleanSession: true,
                    keepalive: 20,
                    sessionExpiryInterval: nil
                )
                try await client.subscribe(topic: topic, qos: 0, subscriptionIdentifier: nil)
                try await client.publish(topic: topic, payload: Data(payload.utf8), qos: 0)
                try await client.disconnect()
                DispatchQueue.main.async {
                    call.resolve(["success": true])
                    self.notifyListeners("subscribed", data: ["topic": topic])
                }
            } catch {
                DispatchQueue.main.async { call.reject("\(error)") }
            }
        }
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        Task {
            do {
                try await client.disconnect()
                DispatchQueue.main.async { call.resolve() }
            } catch {
                DispatchQueue.main.async { call.reject("\(error)") }
            }
        }
    }

    @objc func publish(_ call: CAPPluginCall) {
        let topic = call.getString("topic") ?? ""
        let qos = call.getInt("qos") ?? 0
        let messageExpiryInterval = call.getInt("messageExpiryInterval")
        let contentType = call.getString("contentType")
        
        guard !topic.isEmpty else {
            call.reject("topic is required")
            return
        }

        let data: Data
        if let payloadStr = call.getString("payload") {
            data = Data(payloadStr.utf8)
        } else if let arr = call.getArray("payload") as? [NSNumber] {
            data = Data(arr.map { UInt8(truncating: $0) })
        } else {
            call.reject("payload must be string or number array")
            return
        }

        Task {
            do {
                var properties: [UInt8: Any]? = nil
                if messageExpiryInterval != nil || contentType != nil {
                    properties = [:]
                    if let mei = messageExpiryInterval {
                        properties![MQTT5PropertyType.messageExpiryInterval.rawValue] = UInt32(mei)
                    }
                    if let ct = contentType {
                        properties![MQTT5PropertyType.contentType.rawValue] = ct
                    }
                }
                try await client.publish(topic: topic, payload: data, qos: UInt8(min(qos, 2)), properties: properties)
                DispatchQueue.main.async { call.resolve(["success": true]) }
            } catch {
                let msg = "\(error)"
                let code = (msg.contains("not connected") || msg.lowercased().contains("stream") || msg.lowercased().contains("connection")) ? "CONNECTION_LOST" : "PUBLISH_FAILED"
                DispatchQueue.main.async { call.reject(msg, code, nil) }
            }
        }
    }

    @objc func subscribe(_ call: CAPPluginCall) {
        let topic = call.getString("topic") ?? ""
        let qos = call.getInt("qos") ?? 0
        let subscriptionIdentifier = call.getInt("subscriptionIdentifier")

        guard !topic.isEmpty else {
            call.reject("topic is required")
            return
        }

        Task {
            do {
                try await client.subscribe(topic: topic, qos: UInt8(min(qos, 2)), subscriptionIdentifier: subscriptionIdentifier)
                // Incoming PUBLISH delivered via onPublish set in connect(); no per-topic handler needed
                DispatchQueue.main.async { call.resolve(["success": true]) }
            } catch {
                DispatchQueue.main.async { call.reject("\(error)") }
            }
        }
    }

    @objc func unsubscribe(_ call: CAPPluginCall) {
        let topic = call.getString("topic") ?? ""

        guard !topic.isEmpty else {
            call.reject("topic is required")
            return
        }

        Task {
            do {
                try await client.unsubscribe(topic: topic)
                DispatchQueue.main.async { call.resolve(["success": true]) }
            } catch {
                DispatchQueue.main.async { call.reject("\(error)") }
            }
        }
    }
}
