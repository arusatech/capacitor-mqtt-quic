package ai.annadata.mqttquic.transport

import kotlinx.coroutines.delay

/**
 * StreamReader-like: read(n), readexactly(n).
 * Phase 2 implements over QUIC stream.
 */
interface MQTTStreamReader {
    /** Number of bytes currently buffered (without reading from stream). Used to skip unwanted packets only when safe. */
    suspend fun available(): Int
    suspend fun read(maxBytes: Int): ByteArray
    suspend fun readexactly(n: Int): ByteArray
}

/**
 * StreamWriter-like: write(data), drain(), close().
 */
interface MQTTStreamWriter {
    suspend fun write(data: ByteArray)
    suspend fun drain()
    suspend fun close()
}

/**
 * In-memory buffer for mock read/write (Phase 1 unit tests).
 */
class MockStreamBuffer(initialReadData: ByteArray = ByteArray(0)) {
    var readBuffer = initialReadData.toMutableList()
        private set
    val writeBuffer = mutableListOf<Byte>()
    var isClosed = false
        private set

    fun appendRead(data: ByteArray) {
        readBuffer.addAll(data.toList())
    }

    fun consumeWrite(): ByteArray {
        val d = writeBuffer.toByteArray()
        writeBuffer.clear()
        return d
    }

    fun close() {
        isClosed = true
    }
}

/**
 * Mock reader over MockStreamBuffer.
 */
class MockStreamReader(private val buffer: MockStreamBuffer) : MQTTStreamReader {

    override suspend fun available(): Int = buffer.readBuffer.size

    override suspend fun read(maxBytes: Int): ByteArray {
        if (buffer.isClosed && buffer.readBuffer.isEmpty()) return ByteArray(0)
        val n = minOf(maxBytes, buffer.readBuffer.size)
        if (n == 0) {
            delay(1)
            return read(maxBytes)
        }
        val out = buffer.readBuffer.take(n).toByteArray()
        repeat(n) { buffer.readBuffer.removeAt(0) }
        return out
    }

    override suspend fun readexactly(n: Int): ByteArray {
        val acc = mutableListOf<Byte>()
        while (acc.size < n) {
            if (buffer.isClosed) throw IllegalArgumentException("stream closed")
            val chunk = read(n - acc.size)
            if (chunk.isEmpty()) throw IllegalArgumentException("readexactly")
            acc.addAll(chunk.toList())
        }
        return acc.toByteArray()
    }
}

/**
 * Mock writer over MockStreamBuffer.
 */
class MockStreamWriter(private val buffer: MockStreamBuffer) : MQTTStreamWriter {

    override suspend fun write(data: ByteArray) {
        buffer.writeBuffer.addAll(data.toList())
    }

    override suspend fun drain() {}

    override suspend fun close() {
        buffer.close()
    }
}
