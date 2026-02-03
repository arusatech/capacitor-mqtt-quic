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
        if case .connecting = state {
            lock.unlock()
            throw MQTTProtocolError.insufficientData("already connecting")
        }
        state = .connecting
        lock.unlock()

        do {
            // Determine protocol version
            let useV5 = protocolVersion == .v5 || (protocolVersion == .auto)
            
            let quic: QuicClientProtocol
            #if NGTCP2_ENABLED
            quic = NGTCP2Client()
            #else
            // Build CONNACK stub (used when ngtcp2 is not linked)
            let connack: Data
            if useV5 {
                connack = try MQTT5Protocol.buildConnackV5(reasonCode: .success, sessionPresent: false)
            } else {
                connack = MQTTProtocol.buildConnack(returnCode: MQTTConnAckCode.accepted.rawValue)
            }
            quic = QuicClientStub(initialReadData: connack)
            #endif
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
            let (msgType, remLen, fixed) = try await readFixedHeader(r)
            let rest = try await r.readexactly(remLen)
            var full = Data(fixed)
            full.append(rest)
            let hdrLen = fixed.count
            
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
            let w = writer
            quicClient = nil
            stream = nil
            reader = nil
            writer = nil
            state = .error("\(error)")
            lock.unlock()
            try? await w?.close()
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

        let (_, remLen, fixed) = try await readFixedHeader(r)
        let rest = try await r.readexactly(remLen)
        var full = Data(fixed)
        full.append(rest)
        let hdrLen = fixed.count

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

        let (_, remLen, _) = try await readFixedHeader(r)
        _ = try await r.readexactly(remLen)
    }

    public func disconnect() async throws {
        let task = messageLoopTask
        messageLoopTask = nil
        task?.cancel()
        _ = try? await task?.value

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
        lock.lock()
        defer { lock.unlock() }
        let pid = nextPacketId
        nextPacketId = nextPacketId &+ 1
        if nextPacketId == 0 { nextPacketId = 1 }
        return pid
    }

    /// Read full MQTT fixed header (1 byte type + 1–4 bytes remaining length). Returns (msgType, remLen, fullFixedHeaderData).
    private func readFixedHeader(_ r: MQTTStreamReaderProtocol) async throws -> (UInt8, Int, Data) {
        var fixed = try await r.readexactly(1)
        for _ in 0..<4 {
            do {
                let (rem, _) = try MQTTProtocol.decodeRemainingLength(fixed, offset: 1)
                return (fixed[0], rem, fixed)
            } catch {
                if fixed.count >= 5 { throw error }
                fixed.append(try await r.readexactly(1))
            }
        }
        let (rem, _) = try MQTTProtocol.decodeRemainingLength(fixed, offset: 1)
        return (fixed[0], rem, fixed)
    }

    private func startMessageLoop() {
        messageLoopTask = Task { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                let r: MQTTStreamReaderProtocol?
                self.lock.lock()
                r = self.reader
                self.lock.unlock()
                guard let r = r else { break }

                do {
                    let (msgType, remLen, fixed) = try await self.readFixedHeader(r)
                    let rest = try await r.readexactly(remLen)
                    let type = msgType & 0xF0

                    self.lock.lock()
                    let version = self.activeProtocolVersion
                    let w = self.writer
                    self.lock.unlock()

                    switch type {
                    case MQTTMessageType.PINGREQ.rawValue:
                        if let w = w {
                            let pr = MQTTProtocol.buildPingresp()
                            try await w.write(Data(pr))
                            try await w.drain()
                        }
                    case MQTTMessageType.PUBLISH.rawValue:
                        let qos = (msgType >> 1) & 0x03
                        let (topic, packetId, payload, _) = try MQTTProtocol.parsePublish(Data(rest), offset: 0, qos: qos)

                        self.lock.lock()
                        let cb = self.subscribedTopics[topic]
                        self.lock.unlock()
                        cb?(payload)

                        if qos >= 1, let pid = packetId {
                            self.lock.lock()
                            let wPuback = self.writer
                            self.lock.unlock()
                            if let wPuback = wPuback {
                                let puback = MQTTProtocol.buildPuback(packetId: pid)
                                try await wPuback.write(Data(puback))
                                try await wPuback.drain()
                            }
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
