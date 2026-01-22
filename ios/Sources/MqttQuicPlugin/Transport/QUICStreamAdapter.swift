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

    public func readexactly(_ n: Int) async throws -> Data {
        var acc = Data()
        while acc.count < n {
            let chunk = try await stream.read(maxBytes: n - acc.count)
            if chunk.isEmpty { throw MQTTProtocolError.insufficientData("readexactly") }
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
