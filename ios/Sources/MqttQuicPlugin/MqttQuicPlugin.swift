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

    private var client = MQTTClient(protocolVersion: .auto)

    @objc override public func load() {}

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
        
        // Set protocol version
        let protocolVersion: MQTTClient.ProtocolVersion
        switch protocolVersionStr {
        case "5.0": protocolVersion = .v5
        case "3.1.1": protocolVersion = .v311
        default: protocolVersion = .auto
        }
        client = MQTTClient(protocolVersion: protocolVersion)

        guard !host.isEmpty, !clientId.isEmpty else {
            call.reject("host and clientId are required")
            return
        }

        Task {
            do {
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
        let payload = call.getString("payload") ?? ""
        let qos = call.getInt("qos") ?? 0
        let messageExpiryInterval = call.getInt("messageExpiryInterval")
        let contentType = call.getString("contentType")
        
        guard !topic.isEmpty else {
            call.reject("topic is required")
            return
        }

        Task {
            do {
                let data = Data(payload.utf8)
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

        call.resolve(["success": true])
    }
}
