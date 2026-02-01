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
        CAPPluginMethod(name: "connect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnect", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "publish", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "subscribe", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "unsubscribe", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "testHarness", returnType: CAPPluginReturnPromise)
    ]

    private var client = MQTTClient(protocolVersion: .auto)

    @objc override public func load() {}

    private func bundledCaPath() -> String? {
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
        let keepalive = call.getInt("keepalive") ?? 60
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
                if case .connected = client.getState() {
                    try? await client.disconnect()
                }
                client = MQTTClient(protocolVersion: protocolVersion)
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
                call.resolve(["connected": true])
            } catch {
                call.reject("\(error)")
            }
        }
    }

    @objc func testHarness(_ call: CAPPluginCall) {
        let host = call.getString("host") ?? ""
        let port = call.getInt("port") ?? 1884
        let clientId = call.getString("clientId") ?? "mqttquic_test_client"
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
                    keepalive: 60,
                    sessionExpiryInterval: nil
                )
                try await client.subscribe(topic: topic, qos: 0, subscriptionIdentifier: nil)
                try await client.publish(topic: topic, payload: Data(payload.utf8), qos: 0)
                try await client.disconnect()
                call.resolve(["success": true])
            } catch {
                call.reject("\(error)")
            }
        }
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        Task {
            do {
                try await client.disconnect()
                call.resolve()
            } catch {
                call.reject("\(error)")
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
                call.resolve(["success": true])
            } catch {
                call.reject("\(error)")
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
                call.resolve(["success": true])
            } catch {
                call.reject("\(error)")
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
                call.resolve(["success": true])
            } catch {
                call.reject("\(error)")
            }
        }
    }
}
