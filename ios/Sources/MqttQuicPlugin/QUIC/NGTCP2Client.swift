//
// NGTCP2Client.swift
// MqttQuicPlugin
//
// ngtcp2-based QUIC client implementation.
// Replaces QuicClientStub when ngtcp2 is built and linked.
//
// Build Requirements:
// - ngtcp2 static library (libngtcp2.a)
// - nghttp3 static library (libnghttp3.a)
// - OpenSSL 3.0+ or BoringSSL for TLS 1.3
// - iOS 15.0+ (for Network framework)
//

import Foundation
import NGTCP2Bridge

/// ngtcp2-based QUIC client implementation
public final class NGTCP2Client: QuicClientProtocol {
    
    // MARK: - Properties
    
    /// Native ngtcp2 client handle
    fileprivate var clientHandle: UnsafeMutableRawPointer?
    
    /// Connection state
    private var isConnected: Bool = false
    
    /// Host and port for connection
    private var host: String?
    private var port: UInt16?
    
    /// Active streams
    private var streams: [UInt64: NGTCP2Stream] = [:]
    private let streamLock = NSLock()
    
    // MARK: - Initialization
    
    public init() {
        clientHandle = ngtcp2_client_create()
    }
    
    deinit {
        // Cleanup native handle without capturing self (avoids retain cycle / "deallocated with non-zero retain count").
        let handle = clientHandle
        clientHandle = nil
        if let h = handle {
            Task {
                _ = ngtcp2_client_close(h)
                ngtcp2_client_destroy(h)
            }
        }
    }
    
    // MARK: - QuicClientProtocol Implementation
    
    public func connect(host: String, port: UInt16) async throws {
        guard !isConnected else {
            throw NGTCP2Error.alreadyConnected
        }

        self.host = host
        self.port = port

        guard let handle = clientHandle else {
            throw NGTCP2Error.quicError("native handle not initialized")
        }

        let alpn = "mqtt"
        let rv = host.withCString { hostPtr in
            alpn.withCString { alpnPtr in
                ngtcp2_client_connect(handle, hostPtr, port, alpnPtr)
            }
        }
        if rv != 0 {
            throw NGTCP2Error.quicError(lastErrorMessage())
        }

        isConnected = true
    }
    
    public func openStream() async throws -> QuicStreamProtocol {
        guard isConnected else {
            throw NGTCP2Error.notConnected
        }
        
        streamLock.lock()
        defer { streamLock.unlock() }
        
        guard let handle = clientHandle else {
            throw NGTCP2Error.clientDisconnected
        }

        let streamId = ngtcp2_client_open_stream(handle)
        if streamId < 0 {
            throw NGTCP2Error.quicError(lastErrorMessage())
        }

        let stream = NGTCP2Stream(streamId: UInt64(streamId), client: self)
        streams[UInt64(streamId)] = stream
        
        return stream
    }
    
    public func close() async throws {
        if !isConnected {
            if let handle = clientHandle {
                _ = ngtcp2_client_close(handle)
                ngtcp2_client_destroy(handle)
                clientHandle = nil
            }
            return
        }

        // Close all streams
        streamLock.lock()
        let activeStreams = Array(streams.values)
        streams.removeAll()
        streamLock.unlock()
        
        for stream in activeStreams {
            try? await stream.close()
        }

        if let handle = clientHandle {
            _ = ngtcp2_client_close(handle)
            ngtcp2_client_destroy(handle)
            clientHandle = nil
        }
        
        isConnected = false
    }
    
    // MARK: - Internal Methods (for NGTCP2Stream)
    
    /// Send data on a stream (called by NGTCP2Stream)
    internal func sendStreamData(streamId: UInt64, data: Data) async throws {
        guard isConnected else {
            throw NGTCP2Error.notConnected
        }

        guard let handle = clientHandle else {
            throw NGTCP2Error.clientDisconnected
        }

        let result = data.withUnsafeBytes { buffer in
            ngtcp2_client_write_stream(handle,
                                       Int64(streamId),
                                       buffer.bindMemory(to: UInt8.self).baseAddress,
                                       data.count,
                                       0)
        }
        if result != 0 {
            throw NGTCP2Error.quicError(lastErrorMessage())
        }
    }
    
    /// Receive data from a stream (called by packet receive handler)
    internal func receiveStreamData(streamId: UInt64, data: Data) {
        // Native layer delivers stream data directly; no-op here.
        _ = data
    }
    
    fileprivate func lastErrorMessage() -> String {
        guard let handle = clientHandle, let cStr = ngtcp2_client_last_error(handle) else {
            return "unknown QUIC error"
        }
        return String(cString: cStr)
    }
}

// MARK: - NGTCP2Stream Implementation

/// ngtcp2-based QUIC stream
internal final class NGTCP2Stream: QuicStreamProtocol {
    let streamId: UInt64
    private weak var client: NGTCP2Client?
    private var isClosed: Bool = false
    
    init(streamId: UInt64, client: NGTCP2Client) {
        self.streamId = streamId
        self.client = client
    }
    
    func read(maxBytes: Int) async throws -> Data {
        guard !isClosed else {
            throw NGTCP2Error.streamClosed
        }
        guard let client = client else {
            throw NGTCP2Error.clientDisconnected
        }
        guard let handle = client.clientHandle else {
            throw NGTCP2Error.clientDisconnected
        }

        while !isClosed {
            var buffer = [UInt8](repeating: 0, count: maxBytes)
            let nread = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                let ptr = rawBuffer.bindMemory(to: UInt8.self).baseAddress
                return ngtcp2_client_read_stream(handle, Int64(streamId), ptr, maxBytes)
            }
            if nread < 0 {
                throw NGTCP2Error.quicError(client.lastErrorMessage())
            }
            if nread > 0 {
                return Data(buffer.prefix(Int(nread)))
            }
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms backoff
        }
        return Data()
    }
    
    func write(_ data: Data) async throws {
        guard !isClosed else {
            throw NGTCP2Error.streamClosed
        }
        
        guard let client = client else {
            throw NGTCP2Error.clientDisconnected
        }
        
        try await client.sendStreamData(streamId: streamId, data: data)
    }
    
    func close() async throws {
        isClosed = true

        if let client = client, let handle = client.clientHandle {
            _ = ngtcp2_client_close_stream(handle, Int64(streamId))
        }
    }
    
    /// Called by client when data is received for this stream
    func receiveData(_ data: Data) {
        _ = data
    }
}

// MARK: - Error Types

public enum NGTCP2Error: Error, LocalizedError {
    case notConnected
    case alreadyConnected
    case connectionCancelled
    case streamClosed
    case clientDisconnected
    case tlsError(String)
    case quicError(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "QUIC client is not connected"
        case .alreadyConnected:
            return "QUIC client is already connected"
        case .connectionCancelled:
            return "QUIC connection was cancelled"
        case .streamClosed:
            return "QUIC stream is closed"
        case .clientDisconnected:
            return "QUIC client is disconnected"
        case .tlsError(let message):
            return "TLS error: \(message)"
        case .quicError(let message):
            return "QUIC error: \(message)"
        }
    }
}
