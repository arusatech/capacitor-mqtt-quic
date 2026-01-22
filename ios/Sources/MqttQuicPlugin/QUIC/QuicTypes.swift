//
// QuicTypes.swift
// MqttQuicPlugin
//
// QUIC transport types. Phase 2: ngtcp2 client + single bidirectional stream.
//

import Foundation

/// Represents a single QUIC bidirectional stream (one per MQTT connection).
public protocol QuicStreamProtocol: AnyObject {
    var streamId: UInt64 { get }
    func read(maxBytes: Int) async throws -> Data
    func write(_ data: Data) async throws
    func close() async throws
}

/// QUIC client: connect, TLS handshake, open one bidirectional stream.
public protocol QuicClientProtocol: AnyObject {
    func connect(host: String, port: UInt16) async throws
    func openStream() async throws -> QuicStreamProtocol
    func close() async throws
}
