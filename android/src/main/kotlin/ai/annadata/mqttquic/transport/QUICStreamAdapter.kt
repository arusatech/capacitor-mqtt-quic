package ai.annadata.mqttquic.transport

import ai.annadata.mqttquic.quic.QuicStream

/**
 * MQTTStreamReader over QUIC stream. Mirrors NGTCP2StreamReader.
 */
class QUICStreamReader(private val stream: QuicStream) : MQTTStreamReader {

    override suspend fun read(maxBytes: Int): ByteArray = stream.read(maxBytes)

    override suspend fun readexactly(n: Int): ByteArray {
        val acc = mutableListOf<Byte>()
        while (acc.size < n) {
            val chunk = stream.read(n - acc.size)
            if (chunk.isEmpty()) throw IllegalArgumentException("readexactly")
            acc.addAll(chunk.toList())
        }
        return acc.toByteArray()
    }
}

/**
 * MQTTStreamWriter over QUIC stream. Mirrors NGTCP2StreamWriter.
 */
class QUICStreamWriter(private val stream: QuicStream) : MQTTStreamWriter {

    override suspend fun write(data: ByteArray) {
        stream.write(data)
    }

    override suspend fun drain() {}

    override suspend fun close() {
        stream.close()
    }
}
