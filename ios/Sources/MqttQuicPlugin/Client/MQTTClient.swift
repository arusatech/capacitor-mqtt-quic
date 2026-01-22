//
// MQTTClient.swift
// MqttQuicPlugin
//
// High-level MQTT client: connect, publish, subscribe, disconnect.
// Uses QuicClient + stream adapters + MQTT protocol.
//

import Foundation

public final class MQTTClient {

    public enum State {
        case disconnected
        case connecting
        case connected
        case error(String)
    }
    
    public enum ProtocolVersion {
        case v311
        case v5
        case auto  // Try 5.0 first, fallback to 3.1.1
    }

    private var state: State = .disconnected
    private var protocolVersion: ProtocolVersion = .auto
    private var activeProtocolVersion: UInt8 = 0  // 0x04 or 0x05
    private var quicClient: QuicClientProtocol?
    private var stream: QuicStreamProtocol?
    private var reader: MQTTStreamReaderProtocol?
    private var writer: MQTTStreamWriterProtocol?
    private var messageLoopTask: Task<Void, Error>?
    private var nextPacketId: UInt16 = 1
    private var subscribedTopics: [String: (Data) -> Void] = [:]
    private let lock = NSLock()

    public init(protocolVersion: ProtocolVersion = .auto) {
        self.protocolVersion = protocolVersion
    }

    public func getState() -> State {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    public func connect(host: String, port: UInt16, clientId: String, username: String?, password: String?, cleanSession: Bool, keepalive: UInt16, sessionExpiryInterval: UInt32? = nil) async throws {
        lock.lock()
        state = .connecting
        lock.unlock()

        do {
            // Determine protocol version
            let useV5 = protocolVersion == .v5 || (protocolVersion == .auto)
            
            // Build CONNACK stub (will be replaced with real response)
            let connack: Data
            if useV5 {
                connack = try MQTT5Protocol.buildConnackV5(reasonCode: .success, sessionPresent: false)
            } else {
                connack = MQTTProtocol.buildConnack(returnCode: MQTTConnAckCode.accepted.rawValue)
            }
            
            let quic = QuicClientStub(initialReadData: connack)
            try await quic.connect(host: host, port: port)
            let s = try await quic.openStream()
            let r = QUICStreamReader(stream: s)
            let w = QUICStreamWriter(stream: s)

            lock.lock()
            quicClient = quic
            stream = s
            reader = r
            writer = w
            lock.unlock()

            // Build CONNECT
            let connectData: Data
            if useV5 {
                connectData = try MQTT5Protocol.buildConnectV5(
                    clientId: clientId,
                    username: username,
                    password: password,
                    keepalive: keepalive,
                    cleanStart: cleanSession,
                    sessionExpiryInterval: sessionExpiryInterval
                )
                activeProtocolVersion = MQTTProtocolLevel.v5
            } else {
                connectData = try MQTTProtocol.buildConnect(
                    clientId: clientId,
                    username: username,
                    password: password,
                    keepalive: keepalive,
                    cleanSession: cleanSession
                )
                activeProtocolVersion = MQTTProtocolLevel.v311
            }
            
            try await w.write(connectData)
            try await w.drain()

            // Read CONNACK
            let fixed = try await r.readexactly(2)
            let (msgType, remLen, hdrLen) = try MQTTProtocol.parseFixedHeader(Data(fixed))
            let rest = try await r.readexactly(remLen)
            var full = Data(fixed)
            full.append(rest)
            
            if msgType != MQTTMessageType.CONNACK.rawValue {
                lock.lock()
                state = .error("expected CONNACK, got \(msgType)")
                lock.unlock()
                throw MQTTProtocolError.insufficientData("expected CONNACK")
            }
            
            // Parse CONNACK based on protocol version
            if activeProtocolVersion == MQTTProtocolLevel.v5 {
                let (_, reasonCode, _, _) = try MQTT5Protocol.parseConnackV5(full, offset: hdrLen)
                if reasonCode != .success {
                    lock.lock()
                    state = .error("CONNACK refused: \(reasonCode)")
                    lock.unlock()
                    throw MQTTProtocolError.insufficientData("CONNACK refused: \(reasonCode)")
                }
            } else {
                let (_, returnCode) = try MQTTProtocol.parseConnack(full, offset: hdrLen)
                if returnCode != MQTTConnAckCode.accepted.rawValue {
                    lock.lock()
                    state = .error("CONNACK refused: \(returnCode)")
                    lock.unlock()
                    throw MQTTProtocolError.insufficientData("CONNACK refused")
                }
            }

            lock.lock()
            state = .connected
            lock.unlock()

            startMessageLoop()
        } catch {
            lock.lock()
            state = .error("\(error)")
            lock.unlock()
            throw error
        }
    }

    public func publish(topic: String, payload: Data, qos: UInt8, properties: [UInt8: Any]? = nil) async throws {
        guard case .connected = getState() else { throw MQTTProtocolError.insufficientData("not connected") }
        lock.lock()
        let w = writer
        let version = activeProtocolVersion
        lock.unlock()
        guard let w = w else { throw MQTTProtocolError.insufficientData("no writer") }

        let pid: UInt16? = qos > 0 ? nextPacketIdUsed() : nil
        let data: Data
        if version == MQTTProtocolLevel.v5 {
            data = try MQTT5Protocol.buildPublishV5(topic: topic, payload: payload, packetId: pid, qos: qos, retain: false, properties: properties)
        } else {
            data = try MQTTProtocol.buildPublish(topic: topic, payload: payload, packetId: pid, qos: qos, retain: false)
        }
        try await w.write(data)
        try await w.drain()
    }

    public func subscribe(topic: String, qos: UInt8, subscriptionIdentifier: Int? = nil) async throws {
        guard case .connected = getState() else { throw MQTTProtocolError.insufficientData("not connected") }
        lock.lock()
        let r = reader, w = writer
        let version = activeProtocolVersion
        lock.unlock()
        guard let r = r, let w = w else { throw MQTTProtocolError.insufficientData("no reader/writer") }

        let pid = nextPacketIdUsed()
        let data: Data
        if version == MQTTProtocolLevel.v5 {
            data = try MQTT5Protocol.buildSubscribeV5(packetId: pid, topic: topic, qos: qos, subscriptionIdentifier: subscriptionIdentifier)
        } else {
            data = try MQTTProtocol.buildSubscribe(packetId: pid, topic: topic, qos: qos)
        }
        try await w.write(data)
        try await w.drain()

        let fixed = try await r.readexactly(2)
        let (_, remLen, hdrLen) = try MQTTProtocol.parseFixedHeader(Data(fixed))
        let rest = try await r.readexactly(remLen)
        var full = Data(fixed)
        full.append(rest)
        
        if version == MQTTProtocolLevel.v5 {
            let (_, reasonCodes, _, _) = try MQTT5Protocol.parseSubackV5(full, offset: hdrLen)
            if let firstRC = reasonCodes.first, firstRC != .grantedQoS0 && firstRC != .grantedQoS1 && firstRC != .grantedQoS2 {
                throw MQTTProtocolError.insufficientData("SUBACK error \(firstRC)")
            }
        } else {
            let (_, rc, _) = try MQTTProtocol.parseSuback(full, offset: hdrLen)
            if rc > 0x02 { throw MQTTProtocolError.insufficientData("SUBACK error \(rc)") }
        }
    }

    public func unsubscribe(topic: String) async throws {
        guard case .connected = getState() else { throw MQTTProtocolError.insufficientData("not connected") }
        lock.lock()
        let r = reader, w = writer
        let version = activeProtocolVersion
        subscribedTopics.removeValue(forKey: topic)
        lock.unlock()
        guard let r = r, let w = w else { throw MQTTProtocolError.insufficientData("no reader/writer") }

        let pid = nextPacketIdUsed()
        let data: Data
        if version == MQTTProtocolLevel.v5 {
            data = try MQTT5Protocol.buildUnsubscribeV5(packetId: pid, topics: [topic])
        } else {
            data = try MQTTProtocol.buildUnsubscribe(packetId: pid, topics: [topic])
        }
        try await w.write(data)
        try await w.drain()

        let fixed = try await r.readexactly(2)
        let (_, remLen, _) = try MQTTProtocol.parseFixedHeader(Data(fixed))
        _ = try await r.readexactly(remLen)
    }

    public func disconnect() async throws {
        messageLoopTask?.cancel()
        messageLoopTask = nil
        lock.lock()
        let w = writer
        let version = activeProtocolVersion
        quicClient = nil
        stream = nil
        reader = nil
        writer = nil
        state = .disconnected
        activeProtocolVersion = 0
        lock.unlock()

        if let w = w {
            let data: Data
            if version == MQTTProtocolLevel.v5 {
                data = try MQTT5Protocol.buildDisconnectV5(reasonCode: .normalDisconnectionDisc)
            } else {
                data = MQTTProtocol.buildDisconnect()
            }
            try? await w.write(data)
            try? await w.drain()
            try? await w.close()
        }
    }

    public func onMessage(_ topic: String, _ callback: @escaping (Data) -> Void) {
        lock.lock()
        subscribedTopics[topic] = callback
        lock.unlock()
    }

    private func nextPacketIdUsed() -> UInt16 {
        let pid = nextPacketId
        nextPacketId = nextPacketId &+ 1
        if nextPacketId == 0 { nextPacketId = 1 }
        return pid
    }

    private func startMessageLoop() {
        messageLoopTask = Task {
            guard let r = reader else { return }
            while !Task.isCancelled {
                do {
                    let fixed = try await r.readexactly(2)
                    let (msgType, remLen, _) = try MQTTProtocol.parseFixedHeader(Data(fixed))
                    let rest = try await r.readexactly(remLen)
                    let type = msgType & 0xF0
                    
                    lock.lock()
                    let version = activeProtocolVersion
                    let w = writer
                    lock.unlock()
                    
                    switch type {
                    case MQTTMessageType.PINGREQ.rawValue:
                        if let w = w {
                            let pr = MQTTProtocol.buildPingresp()
                            try await w.write(Data(pr))
                            try await w.drain()
                        }
                    case MQTTMessageType.PUBLISH.rawValue:
                        let qos = (msgType >> 1) & 0x03
                        // For MQTT 5.0, properties come after topic/packetId, but we can use same parser
                        // (properties are in the payload section, parsePublish handles topic + packetId + payload)
                        let (topic, packetId, payload, _) = try MQTTProtocol.parsePublish(Data(rest), offset: 0, qos: qos)
                        
                        lock.lock()
                        let cb = subscribedTopics[topic]
                        lock.unlock()
                        cb?(payload)
                        
                        // Send PUBACK if QoS >= 1
                        if qos >= 1, let pid = packetId, let w = w {
                            let puback = MQTTProtocol.buildPuback(packetId: pid)
                            try await w.write(Data(puback))
                            try await w.drain()
                        }
                    default:
                        break
                    }
                } catch {
                    if !Task.isCancelled { break }
                }
            }
        }
    }
}
