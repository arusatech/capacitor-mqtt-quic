package ai.annadata.mqttquic.quic

/**
 * QUIC stream: one bidirectional stream per MQTT connection.
 * Phase 2: ngtcp2 client + single stream.
 */
interface QuicStream {
    val streamId: Long
    suspend fun read(maxBytes: Int): ByteArray
    suspend fun write(data: ByteArray)
    suspend fun close()
}

/**
 * QUIC client: connect, TLS handshake, open one bidirectional stream.
 */
interface QuicClient {
    suspend fun connect(host: String, port: Int, connectAddress: String? = null)
    suspend fun openStream(): QuicStream
    suspend fun close()
}
