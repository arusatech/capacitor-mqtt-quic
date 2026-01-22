//
// QuicClientStub.swift
// MqttQuicPlugin
//
// Stub QUIC client for Phase 2. Replace with ngtcp2-backed implementation when
// ngtcp2 is built for iOS (see README). Uses in-memory stream for testing.
//

import Foundation

/// Stub stream: buffers read/write in memory. Used when ngtcp2 is not linked.
public final class QuicStreamStub: QuicStreamProtocol {
    public let streamId: UInt64
    private let buffer: MockStreamBuffer

    public init(streamId: UInt64, buffer: MockStreamBuffer) {
        self.streamId = streamId
        self.buffer = buffer
    }

    public func read(maxBytes: Int) async throws -> Data {
        let reader = MockStreamReader(buffer: buffer)
        return try await reader.read(maxBytes: maxBytes)
    }

    public func write(_ data: Data) async throws {
        let writer = MockStreamWriter(buffer: buffer)
        try await writer.write(data)
    }

    public func close() async throws {
        buffer.isClosed = true
    }
}

/// Stub QUIC client. connect() succeeds without network; openStream() returns a stub stream.
/// Phase 2 proper: use ngtcp2_conn_client_new, TLS 1.3, NWConnection for UDP.
/// Pass initialReadData (e.g. CONNACK) to simulate server response for testing.
public final class QuicClientStub: QuicClientProtocol {
    private var streamId: UInt64 = 0
    private var buffer: MockStreamBuffer?
    private var _stream: QuicStreamStub?
    private let initialReadData: Data

    public init(initialReadData: Data = Data()) {
        self.initialReadData = initialReadData
    }

    public func connect(host: String, port: UInt16) async throws {
        buffer = MockStreamBuffer(initialReadData: initialReadData)
        streamId = 0
    }

    public func openStream() async throws -> QuicStreamProtocol {
        guard let buf = buffer else { throw NSError(domain: "QuicClientStub", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"]) }
        let s = QuicStreamStub(streamId: streamId, buffer: buf)
        streamId += 1
        _stream = s
        return s
    }

    public func close() async throws {
        _stream = nil
        buffer = nil
    }
}
