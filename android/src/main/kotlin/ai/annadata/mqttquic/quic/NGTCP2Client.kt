package ai.annadata.mqttquic.quic

import android.util.Log
import kotlinx.coroutines.delay

/**
 * ngtcp2-based QUIC client implementation for Android.
 * Replaces QuicClientStub when ngtcp2 is built and linked via JNI.
 *
 * Build Requirements:
 * - ngtcp2 native library (libngtcp2_client.so)
 * - nghttp3 static library (libnghttp3.a)
 * - OpenSSL 3.0+ or BoringSSL for TLS 1.3
 * - Android NDK r25+
 * - Android API 21+ (Android 5.0+)
 */
class NGTCP2Client : QuicClient {
    
    companion object {
        private const val TAG = "NGTCP2Client"
        private var nativeAvailable: Boolean = false

        init {
            nativeAvailable = try {
                System.loadLibrary("ngtcp2_client")
                true
            } catch (e: UnsatisfiedLinkError) {
                false
            } catch (e: Exception) {
                false
            }

            if (!nativeAvailable) {
                Log.w(TAG, "ngtcp2_client native library not available")
            }
        }

        fun isAvailable(): Boolean = nativeAvailable
    }
    
    // Native methods (implemented in ngtcp2_jni.cpp)
    private external fun nativeCreateConnection(host: String, port: Int): Long
    private external fun nativeConnect(connHandle: Long): Int
    private external fun nativeOpenStream(connHandle: Long): Long
    private external fun nativeWriteStream(connHandle: Long, streamId: Long, data: ByteArray): Int
    private external fun nativeReadStream(connHandle: Long, streamId: Long): ByteArray?
    private external fun nativeClose(connHandle: Long)
    private external fun nativeIsConnected(connHandle: Long): Boolean
    internal external fun nativeCloseStream(connHandle: Long, streamId: Long): Int
    internal external fun nativeGetLastError(connHandle: Long): String
    
    // Connection state
    private var connHandle: Long = 0
    private var isConnected: Boolean = false
    private val streams = mutableMapOf<Long, NGTCP2Stream>()
    
    override suspend fun connect(host: String, port: Int) {
        if (!isAvailable()) {
            throw IllegalStateException("ngtcp2 native library is not loaded")
        }
        if (isConnected) {
            throw IllegalStateException("Already connected")
        }
        
        // Create native connection
        connHandle = nativeCreateConnection(host, port)
        if (connHandle == 0L) {
            throw IllegalStateException("Failed to create QUIC connection")
        }
        
        // Connect to server
        val result = nativeConnect(connHandle)
        if (result != 0) {
            throw Exception("QUIC connection failed: ${nativeGetLastError(connHandle)}")
        }
        isConnected = true
    }
    
    override suspend fun openStream(): QuicStream {
        if (!isConnected) {
            throw IllegalStateException("Not connected")
        }
        
        val streamId = nativeOpenStream(connHandle)
        if (streamId < 0L) {
            throw IllegalStateException("Failed to open QUIC stream: ${nativeGetLastError(connHandle)}")
        }
        
        val stream = NGTCP2Stream(connHandle, streamId, this)
        streams[streamId] = stream
        
        return stream
    }
    
    override suspend fun close() {
        if (!isConnected) {
            return
        }
        
        // Close all streams
        streams.values.forEach { stream ->
            try {
                stream.close()
            } catch (e: Exception) {
                // Ignore errors during stream close
            }
        }
        streams.clear()
        
        // Close native connection
        nativeClose(connHandle)
        connHandle = 0
        
        isConnected = false
    }
    
    /**
     * Internal method called by NGTCP2Stream to write data
     */
    internal suspend fun writeStreamData(streamId: Long, data: ByteArray): Int {
        if (!isConnected) {
            throw IllegalStateException("Not connected")
        }
        return nativeWriteStream(connHandle, streamId, data)
    }
    
    /**
     * Internal method called to read data from stream
     */
    internal suspend fun readStreamData(streamId: Long): ByteArray? {
        if (!isConnected) {
            throw IllegalStateException("Not connected")
        }
        return nativeReadStream(connHandle, streamId)
    }
}

/**
 * ngtcp2-based QUIC stream implementation
 */
internal class NGTCP2Stream(
    private val connHandle: Long,
    override val streamId: Long,
    private val client: NGTCP2Client
) : QuicStream {
    
    private var isClosed: Boolean = false
    
    override suspend fun read(maxBytes: Int): ByteArray {
        if (isClosed) {
            throw IllegalStateException("Stream is closed")
        }

        while (!isClosed) {
            val data = client.readStreamData(streamId)
            if (data != null && data.isNotEmpty()) {
                return data
            }
            delay(5)
        }
        return ByteArray(0)
    }
    
    override suspend fun write(data: ByteArray) {
        if (isClosed) {
            throw IllegalStateException("Stream is closed")
        }
        
        // Write data to native stream
        val result = client.writeStreamData(streamId, data)
        if (result != 0) {
            throw Exception("Failed to write to stream: ${client.nativeGetLastError(connHandle)}")
        }
    }
    
    override suspend fun close() {
        if (isClosed) {
            return
        }

        client.nativeCloseStream(connHandle, streamId)
        isClosed = true
    }
}
