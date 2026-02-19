package ai.annadata.mqttquic.quic

import ai.annadata.mqttquic.transport.MockStreamBuffer
import ai.annadata.mqttquic.transport.MockStreamReader
import ai.annadata.mqttquic.transport.MockStreamWriter

/**
 * Stub QUIC stream. Phase 2: replace with ngtcp2-backed implementation.
 */
class QuicStreamStub(
    override val streamId: Long,
    private val buffer: MockStreamBuffer
) : QuicStream {

    private val reader = MockStreamReader(buffer)
    private val writer = MockStreamWriter(buffer)

    override suspend fun read(maxBytes: Int): ByteArray = reader.read(maxBytes)

    override suspend fun write(data: ByteArray) {
        writer.write(data)
    }

    override suspend fun close() {
        writer.close()
    }
}

/**
 * Stub QUIC client. connect() succeeds without network; openStream() returns stub stream.
 * Phase 2 proper: ngtcp2 + JNI, DatagramSocket for UDP.
 * Pass initialReadData (e.g. CONNACK) to simulate server response for testing.
 */
class QuicClientStub(private val initialReadData: List<Byte> = emptyList()) : QuicClient {

    private var buffer: MockStreamBuffer? = null
    private var streamId = 0L

    override suspend fun connect(host: String, port: Int, connectAddress: String?) {
        buffer = MockStreamBuffer(initialReadData.toByteArray())
        streamId = 0L
    }

    override suspend fun openStream(): QuicStream {
        val buf = buffer ?: error("Not connected")
        val s = QuicStreamStub(streamId, buf)
        streamId++
        return s
    }

    override suspend fun close() {
        buffer = null
    }
}
