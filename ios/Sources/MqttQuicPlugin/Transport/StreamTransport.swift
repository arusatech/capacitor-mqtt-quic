//
// StreamTransport.swift
// MqttQuicPlugin
//
// Transport abstraction: StreamReader-like and StreamWriter-like.
// Phase 2 will implement these over QUIC streams; Phase 1 uses mocks for tests.
//

import Foundation

/// StreamReader-like interface: read(n), readexactly(n).
/// Async where applicable (Phase 2 uses async).
public protocol MQTTStreamReaderProtocol: AnyObject {
    func read(maxBytes: Int) async throws -> Data
    func readexactly(_ n: Int) async throws -> Data
}

/// StreamWriter-like interface: write(data), drain(), close().
public protocol MQTTStreamWriterProtocol: AnyObject {
    func write(_ data: Data) async throws
    func drain() async throws
    func close() async throws
}

// MARK: - Mock implementations (Phase 1 unit tests)

/// In-memory buffer for mock read/write.
public final class MockStreamBuffer {
    public private(set) var readBuffer: Data
    public private(set) var writeBuffer: Data
    public var isClosed: Bool = false

    public init(initialReadData: Data = Data()) {
        self.readBuffer = initialReadData
        self.writeBuffer = Data()
    }

    public func appendRead(_ data: Data) {
        readBuffer.append(data)
    }

    public func consumeRead(maxBytes: Int) -> Data {
        let n = min(maxBytes, readBuffer.count)
        let out = readBuffer.prefix(n)
        readBuffer = readBuffer.dropFirst(n)
        return Data(out)
    }

    public func appendWrite(_ data: Data) {
        writeBuffer.append(data)
    }

    public func consumeWrite() -> Data {
        let d = writeBuffer
        writeBuffer = Data()
        return d
    }
}

/// Mock reader: reads from MockStreamBuffer.
public final class MockStreamReader: MQTTStreamReaderProtocol {
    private let buffer: MockStreamBuffer

    public init(buffer: MockStreamBuffer) {
        self.buffer = buffer
    }

    public func read(maxBytes: Int) async throws -> Data {
        if buffer.isClosed && buffer.readBuffer.isEmpty {
            return Data()
        }
        let n = min(maxBytes, buffer.readBuffer.count)
        guard n > 0 else {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return try await read(maxBytes: maxBytes)
        }
        return buffer.consumeRead(maxBytes: n)
    }

    public func readexactly(_ n: Int) async throws -> Data {
        var acc = Data()
        while acc.count < n {
            if buffer.isClosed { throw MQTTProtocolError.insufficientData("stream closed") }
            let chunk = try await read(maxBytes: n - acc.count)
            if chunk.isEmpty { throw MQTTProtocolError.insufficientData("readexactly") }
            acc.append(chunk)
        }
        return acc
    }
}

/// Mock writer: appends to MockStreamBuffer.
public final class MockStreamWriter: MQTTStreamWriterProtocol {
    private let buffer: MockStreamBuffer

    public init(buffer: MockStreamBuffer) {
        self.buffer = buffer
    }

    public func write(_ data: Data) async throws {
        buffer.appendWrite(data)
    }

    public func drain() async throws {}

    public func close() async throws {
        buffer.isClosed = true
    }
}
