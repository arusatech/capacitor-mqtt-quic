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
        var emptyCount = 0
        let maxEmptyRetries = 60  // ~300ms total (60 * 5ms) so SUBACK can arrive
        while acc.count < n {
            let chunk = try await stream.read(maxBytes: n - acc.count)
            if chunk.isEmpty {
                emptyCount += 1
                if emptyCount >= maxEmptyRetries {
                    throw MQTTProtocolError.insufficientData("readexactly")
                }
                try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
                continue
            }
            emptyCount = 0
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
