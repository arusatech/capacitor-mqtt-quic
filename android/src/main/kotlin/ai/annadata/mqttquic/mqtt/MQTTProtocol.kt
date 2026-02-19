package ai.annadata.mqttquic.mqtt

import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets

/**
 * MQTT 3.1.1 encode/decode. Matches MQTTD mqttd/protocol.py.
 */
object MQTTProtocol {

    const val PROTOCOL_NAME = "MQTT"

    /**
     * Encode remaining length (1–4 bytes). Max 268_435_455.
     */
    fun encodeRemainingLength(length: Int): ByteArray {
        if (length < 0 || length > 268_435_455) {
            throw IllegalArgumentException("Invalid remaining length: $length")
        }
        val enc = mutableListOf<Byte>()
        var n = length
        do {
            var b = (n % 128).toByte()
            n /= 128
            if (n > 0) b = (b.toInt() or 0x80).toByte()
            enc.add(b)
        } while (n > 0)
        return enc.toByteArray()
    }

    /**
     * Decode remaining length. Returns Pair(length, bytesConsumed).
     */
    fun decodeRemainingLength(data: ByteArray, offset: Int = 0): Pair<Int, Int> {
        var mul = 1
        var len = 0
        var i = offset
        repeat(4) {
            if (i >= data.size) throw IllegalArgumentException("Insufficient data for remaining length")
            val b = data[i].toInt() and 0xFF
            len += (b and 0x7F) * mul
            i++
            if ((b and 0x80) == 0) return len to (i - offset)
            mul *= 128
        }
        throw IllegalArgumentException("Invalid remaining length (max 4 bytes)")
    }

    fun encodeString(s: String): ByteArray {
        val utf8 = s.toByteArray(StandardCharsets.UTF_8)
        if (utf8.size > 0xFFFF) throw IllegalArgumentException("String too long")
        return byteArrayOf(
            (utf8.size shr 8).toByte(),
            (utf8.size and 0xFF).toByte()
        ) + utf8
    }

    fun decodeString(data: ByteArray, offset: Int): Pair<String, Int> {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for string length")
        val strLen = ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
        val start = offset + 2
        if (start + strLen > data.size) throw IllegalArgumentException("Insufficient data for string content")
        val sub = data.copyOfRange(start, start + strLen)
        val s = String(sub, StandardCharsets.UTF_8)
        return s to (start + strLen)
    }

    /**
     * Returns Triple(messageType, remainingLength, bytesConsumed).
     */
    fun parseFixedHeader(data: ByteArray): Triple<Byte, Int, Int> {
        if (data.size < 2) throw IllegalArgumentException("Insufficient data for fixed header")
        val msgType = data[0]
        val (rem, consumed) = decodeRemainingLength(data, 1)
        return Triple(msgType, rem, 1 + consumed)
    }

    /**
     * Returns total MQTT packet length (fixed header + payload) if buffer has at least a decodable fixed header, else null.
     * Use when draining stream: accumulate bytes, then call this; when buffer.size >= length, you have a complete packet.
     */
    fun getNextPacketLength(buffer: ByteArray): Int? {
        if (buffer.size < 2) return null
        // CONNACK (0x20): often single-byte remaining length (e.g. 0x20 = 32 → total 34). Handle that first.
        if (buffer[0].toInt() and 0xFF == 0x20) {
            val b1 = buffer[1].toInt() and 0xFF
            if ((b1 and 0x80) == 0) {
                val rem = b1
                val total = 1 + 1 + rem
                if (total <= buffer.size) return total
            } else {
                try {
                    val (rem, consumed) = decodeRemainingLength(buffer, 1)
                    val total = 1 + consumed + rem
                    if (total <= buffer.size) return total
                } catch (_: IllegalArgumentException) { /* fall through */ }
            }
        }
        for (len in minOf(5, buffer.size) downTo 2) {
            try {
                val (_, rem, fixedLen) = parseFixedHeader(buffer.copyOf(len))
                val total = fixedLen + rem
                if (total in 1..buffer.size) return total
            } catch (_: IllegalArgumentException) { /* need more bytes for remaining length */ }
        }
        return null
    }

    fun buildConnect(
        clientId: String,
        username: String? = null,
        password: String? = null,
        keepalive: Int = 20,
        cleanSession: Boolean = true
    ): ByteArray {
        val variableHeader = mutableListOf<Byte>()
        variableHeader.addAll(encodeString(PROTOCOL_NAME).toList())
        variableHeader.add(MQTTProtocolLevel.V311)
        var flags = 0
        if (cleanSession) flags = flags or MQTTConnectFlags.CLEAN_SESSION
        if (username != null) flags = flags or MQTTConnectFlags.USERNAME
        if (password != null) flags = flags or MQTTConnectFlags.PASSWORD
        variableHeader.add(flags.toByte())
        variableHeader.add((keepalive shr 8).toByte())
        variableHeader.add((keepalive and 0xFF).toByte())

        val payload = mutableListOf<Byte>()
        payload.addAll(encodeString(clientId).toList())
        username?.let { payload.addAll(encodeString(it).toList()) }
        password?.let { payload.addAll(encodeString(it).toList()) }

        val remLen = variableHeader.size + payload.size
        val fixed = mutableListOf<Byte>()
        fixed.add(MQTTMessageType.CONNECT)
        fixed.addAll(encodeRemainingLength(remLen).toList())

        return (fixed + variableHeader + payload).toByteArray()
    }

    fun buildConnack(returnCode: Int = MQTTConnAckCode.ACCEPTED): ByteArray {
        return byteArrayOf(
            MQTTMessageType.CONNACK,
            *encodeRemainingLength(2),
            0x00,
            returnCode.toByte()
        )
    }

    /**
     * Parse CONNACK variable header. Returns Pair(sessionPresent, returnCode).
     */
    fun parseConnack(data: ByteArray, offset: Int = 0): Pair<Boolean, Int> {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for CONNACK")
        val flags = data[offset].toInt() and 0xFF
        val rc = data[offset + 1].toInt() and 0xFF
        return ((flags and 0x01) != 0) to rc
    }

    fun buildPublish(
        topic: String,
        payload: ByteArray,
        packetId: Int? = null,
        qos: Int = 0,
        retain: Boolean = false
    ): ByteArray {
        var msgType = MQTTMessageType.PUBLISH.toInt()
        if (qos > 0) msgType = msgType or (qos shl 1)
        if (retain) msgType = msgType or 0x01

        val vh = mutableListOf<Byte>()
        vh.addAll(encodeString(topic).toList())
        if (qos > 0 && packetId != null) {
            vh.add((packetId shr 8).toByte())
            vh.add((packetId and 0xFF).toByte())
        }
        val vhArr = vh.toByteArray()
        val pl = vhArr + payload
        val remLen = pl.size
        return byteArrayOf(
            msgType.toByte(),
            *encodeRemainingLength(remLen),
            *pl
        )
    }

    fun buildPuback(packetId: Int): ByteArray {
        return byteArrayOf(
            MQTTMessageType.PUBACK,
            *encodeRemainingLength(2),
            (packetId shr 8).toByte(),
            (packetId and 0xFF).toByte()
        )
    }

    fun buildPubrec(packetId: Int): ByteArray {
        return byteArrayOf(
            MQTTMessageType.PUBREC,
            *encodeRemainingLength(2),
            (packetId shr 8).toByte(),
            (packetId and 0xFF).toByte()
        )
    }

    fun buildPubrel(packetId: Int): ByteArray {
        return byteArrayOf(
            MQTTMessageType.PUBREL,
            *encodeRemainingLength(2),
            (packetId shr 8).toByte(),
            (packetId and 0xFF).toByte()
        )
    }

    fun buildPubcomp(packetId: Int): ByteArray {
        return byteArrayOf(
            MQTTMessageType.PUBCOMP,
            *encodeRemainingLength(2),
            (packetId shr 8).toByte(),
            (packetId and 0xFF).toByte()
        )
    }

    /** Parse PUBREL variable header; returns packet identifier. */
    fun parsePubrel(data: ByteArray, offset: Int = 0): Int {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for PUBREL")
        return ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
    }

    fun parsePuback(data: ByteArray, offset: Int = 0): Int {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for PUBACK")
        return ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
    }
    
    /**
     * Parse PUBLISH payload (after fixed header).
     * Returns (topic, packetId?, payload). packetId only for QoS > 0.
     */
    fun parsePublish(data: ByteArray, offset: Int, qos: Int): Triple<String, Int?, ByteArray> {
        var off = offset
        val (topic, next) = decodeString(data, off)
        off = next
        var pid: Int? = null
        if (qos > 0) {
            if (off + 2 > data.size) throw IllegalArgumentException("Insufficient data for PUBLISH packet ID")
            pid = ((data[off].toInt() and 0xFF) shl 8) or (data[off + 1].toInt() and 0xFF)
            off += 2
        }
        val payload = data.copyOfRange(off, data.size)
        return Triple(topic, pid, payload)
    }

    fun buildSubscribe(packetId: Int, topic: String, qos: Int = 0): ByteArray {
        val vh = byteArrayOf((packetId shr 8).toByte(), (packetId and 0xFF).toByte())
        val pl = encodeString(topic) + byteArrayOf((qos and 0x03).toByte())
        val rem = vh.size + pl.size
        return byteArrayOf(
            (MQTTMessageType.SUBSCRIBE.toInt() or 0x02).toByte(),
            *encodeRemainingLength(rem),
            *vh,
            *pl
        )
    }

    fun buildSuback(packetId: Int, returnCode: Int = 0): ByteArray {
        return byteArrayOf(
            MQTTMessageType.SUBACK,
            *encodeRemainingLength(3),
            (packetId shr 8).toByte(),
            (packetId and 0xFF).toByte(),
            returnCode.toByte()
        )
    }

    fun parseSuback(data: ByteArray, offset: Int = 0): Triple<Int, Int, Int> {
        if (offset + 3 > data.size) throw IllegalArgumentException("Insufficient data for SUBACK")
        val pid = ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
        val rc = data[offset + 2].toInt() and 0xFF
        return Triple(pid, rc, offset + 3)
    }

    fun buildUnsubscribe(packetId: Int, topics: List<String>): ByteArray {
        val vh = byteArrayOf((packetId shr 8).toByte(), (packetId and 0xFF).toByte())
        val plList = topics.flatMap { encodeString(it).toList() }
        val pl = ByteArray(plList.size) { plList[it] }
        val rem = vh.size + pl.size
        return byteArrayOf(
            (MQTTMessageType.UNSUBSCRIBE.toInt() or 0x02).toByte(),
            *encodeRemainingLength(rem),
            *vh,
            *pl
        )
    }

    fun buildUnsuback(packetId: Int): ByteArray {
        return byteArrayOf(
            MQTTMessageType.UNSUBACK,
            *encodeRemainingLength(2),
            (packetId shr 8).toByte(),
            (packetId and 0xFF).toByte()
        )
    }

    fun buildPingreq(): ByteArray {
        return byteArrayOf(MQTTMessageType.PINGREQ, *encodeRemainingLength(0))
    }

    fun buildPingresp(): ByteArray {
        return byteArrayOf(MQTTMessageType.PINGRESP, *encodeRemainingLength(0))
    }

    fun buildDisconnect(): ByteArray {
        return byteArrayOf(MQTTMessageType.DISCONNECT, *encodeRemainingLength(0))
    }
}
