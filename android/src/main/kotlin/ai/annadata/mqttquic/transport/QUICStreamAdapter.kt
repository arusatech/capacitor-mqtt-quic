package ai.annadata.mqttquic.transport

import android.util.Log
import ai.annadata.mqttquic.mqtt.MQTTProtocol
import ai.annadata.mqttquic.quic.QuicStream
import kotlinx.coroutines.delay

/**
 * MQTTStreamReader over QUIC stream. Buffers excess bytes so readexactly(n)
 * and read(maxBytes) get exactly the requested amount; native may return
 * a full CONNACK (e.g. 18 bytes) in one read, so we must not lose the remainder.
 *
 * Efficient CONNACK/packet read: call [drain] to read until the stream has no more
 * data, then [tryConsumeNextPacket] to take the first complete MQTT packet from
 * the buffer. Repeat drain + tryConsumeNextPacket (with short delay) until you
 * get a packet or timeout.
 */
class QUICStreamReader(private val stream: QuicStream) : MQTTStreamReader {

    private val buffer = mutableListOf<Byte>()

    override suspend fun available(): Int = buffer.size

    /** Read from stream until no more data is available (drained). Call before tryConsumeNextPacket. */
    suspend fun drain() {
        while (true) {
            val chunk = stream.read(8192)
            if (chunk.isEmpty()) break
            Log.i("MQTTClient", "QUICStreamReader: drain got ${chunk.size} bytes bufferTotal=${buffer.size + chunk.size}")
            buffer.addAll(chunk.toList())
        }
    }

    /** Consume the first n bytes from buffer and return them. Caller must ensure buffer.size >= n. */
    fun consume(n: Int): ByteArray {
        if (buffer.size < n) throw IllegalArgumentException("buffer has ${buffer.size} < $n")
        val out = buffer.take(n).toByteArray()
        repeat(n) { buffer.removeAt(0) }
        return out
    }

    /**
     * If buffer contains at least one complete MQTT packet (fixed header + payload), consume and return it; else return null.
     * Call after [drain]; if null, delay and drain again (or timeout).
     */
    fun tryConsumeNextPacket(): ByteArray? {
        val buf = buffer.toByteArray()
        val totalLen = MQTTProtocol.getNextPacketLength(buf)
        if (totalLen == null) {
            if (buf.isNotEmpty()) {
                Log.w("MQTTClient", "QUICStreamReader: getNextPacketLength returned null bufferSize=${buf.size} firstByte=0x${Integer.toHexString(buf[0].toInt() and 0xFF)}")
            }
            return null
        }
        if (buffer.size < totalLen) {
            Log.i("MQTTClient", "QUICStreamReader: buffer.size=${buffer.size} < totalLen=$totalLen waiting for more")
            return null
        }
        val packet = consume(totalLen)
        Log.i("MQTTClient", "QUICStreamReader: tryConsumeNextPacket consumed $totalLen bytes type=0x${Integer.toHexString(packet[0].toInt() and 0xFF)}")
        return packet
    }

    override suspend fun read(maxBytes: Int): ByteArray {
        while (buffer.size < maxBytes) {
            val chunk = stream.read(maxBytes - buffer.size)
            if (chunk.isEmpty()) break
            Log.i("MQTTClient", "QUICStreamReader: got chunk=${chunk.size} bufferSize=${buffer.size + chunk.size}")
            buffer.addAll(chunk.toList())
        }
        val n = minOf(maxBytes, buffer.size)
        if (n == 0) return ByteArray(0)
        val result = buffer.subList(0, n).toByteArray()
        repeat(n) { buffer.removeAt(0) }
        Log.i("MQTTClient", "QUICStreamReader: returning $n bytes bufferRemain=${buffer.size}")
        return result
    }

    override suspend fun readexactly(n: Int): ByteArray {
        Log.i("MQTTClient", "QUICStreamReader: readexactly($n) bufferHas=${buffer.size}")
        val acc = mutableListOf<Byte>()
        while (acc.size < n) {
            drain()
            val fromBuffer = minOf(n - acc.size, buffer.size)
            if (fromBuffer > 0) {
                acc.addAll(buffer.subList(0, fromBuffer).toList())
                repeat(fromBuffer) { buffer.removeAt(0) }
            } else {
                // No data yet (e.g. message loop waiting for SUBACK/PUBLISH). Wait and retry instead of throwing.
                delay(20L)
            }
        }
        Log.i("MQTTClient", "QUICStreamReader: readexactly($n) done")
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
