//
// QUICStreamAdapter.swift
// MqttQuicPlugin
//
// StreamReader/StreamWriter over QUIC stream. Mirrors NGTCP2StreamReader/NGTCP2StreamWriter.
//

import Foundation

/// MQTTStreamReader over a QuicStream.
public final class QUICStreamReader: MQTTStreamReaderProtocol {
    private let stream: QuicStreamProtocol

    public init(stream: QuicStreamProtocol) {
        self.stream = stream
    }

    public func read(maxBytes: Int) async throws -> Data {
        try await stream.read(maxBytes: maxBytes)
    }

    /// Read exactly n bytes. Waits indefinitely for data (matches Android behavior).
    /// Previously had a 300ms limit which caused message loop to throw and disconnect before PUBLISH packets arrived.
    public func readexactly(_ n: Int) async throws -> Data {
        var acc = Data()
        while acc.count < n {
            let chunk = try await stream.read(maxBytes: n - acc.count)
            if chunk.isEmpty {
                try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
                continue
            }
            acc.append(chunk)
        }
        return acc
    }
}

/// MQTTStreamWriter over a QuicStream.
public final class QUICStreamWriter: MQTTStreamWriterProtocol {
    private let stream: QuicStreamProtocol

    public init(stream: QuicStreamProtocol) {
        self.stream = stream
    }

    public func write(_ data: Data) async throws {
        try await stream.write(data)
    }

    public func drain() async throws {}

    public func close() async throws {
        try await stream.close()
    }
}
