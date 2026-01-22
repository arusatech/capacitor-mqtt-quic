package ai.annadata.mqttquic.mqtt

import ai.annadata.mqttquic.transport.MockStreamBuffer
import ai.annadata.mqttquic.transport.MockStreamReader
import ai.annadata.mqttquic.transport.MockStreamWriter
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class MQTTProtocolTest {

    @Test
    fun encodeDecodeRemainingLength() {
        for ((len, bytes) in listOf(0 to 1, 127 to 1, 128 to 2, 16383 to 2, 16384 to 3, 2097151 to 3, 2097152 to 4)) {
            val enc = MQTTProtocol.encodeRemainingLength(len)
            assertEquals("length $len", bytes, enc.size)
            val (dec, _) = MQTTProtocol.decodeRemainingLength(enc, 0)
            assertEquals(len, dec)
        }
    }

    @Test
    fun encodeDecodeString() {
        val s = "hello/mqtt"
        val enc = MQTTProtocol.encodeString(s)
        assertEquals(2 + s.toByteArray(Charsets.UTF_8).size, enc.size)
        val (dec, _) = MQTTProtocol.decodeString(enc, 0)
        assertEquals(s, dec)
    }

    @Test
    fun buildConnect() {
        val data = MQTTProtocol.buildConnect("test-client", "u", "p", 90, true)
        assert(data.size >= 10)
        assertEquals(MQTTMessageType.CONNECT, data[0])
    }

    @Test
    fun buildConnack() {
        val data = MQTTProtocol.buildConnack(MQTTConnAckCode.ACCEPTED)
        assertEquals(4, data.size)
        assertEquals(MQTTMessageType.CONNACK, data[0])
        assertEquals(MQTTConnAckCode.ACCEPTED, data[3].toInt() and 0xFF)
    }

    @Test
    fun buildPublish() {
        val payload = "hello".toByteArray(Charsets.UTF_8)
        val data = MQTTProtocol.buildPublish("a/b", payload, null, 0, false)
        assert((data[0].toInt() and 0xF0) == (MQTTMessageType.PUBLISH.toInt() and 0xF0))
    }

    @Test
    fun buildSubscribeAndSuback() {
        val sub = MQTTProtocol.buildSubscribe(1, "t/1", 0)
        assertEquals((MQTTMessageType.SUBSCRIBE.toInt() or 0x02).toByte(), sub[0])

        val suback = MQTTProtocol.buildSuback(1, 0)
        assertEquals(MQTTMessageType.SUBACK, suback[0])
        val (pid, rc, _) = MQTTProtocol.parseSuback(suback, 2)
        assertEquals(1, pid)
        assertEquals(0, rc)
    }

    @Test
    fun buildPingreqPingrespDisconnect() {
        val pr = MQTTProtocol.buildPingreq()
        assertEquals(MQTTMessageType.PINGREQ, pr[0])
        val ps = MQTTProtocol.buildPingresp()
        assertEquals(MQTTMessageType.PINGRESP, ps[0])
        val dc = MQTTProtocol.buildDisconnect()
        assertEquals(MQTTMessageType.DISCONNECT, dc[0])
    }

    @Test
    fun mockStreamReaderWriter() = runBlocking {
        val buf = MockStreamBuffer(byteArrayOf(1, 2, 3, 4, 5))
        val reader = MockStreamReader(buf)
        val writer = MockStreamWriter(buf)

        val r1 = reader.read(2)
        assertEquals(byteArrayOf(1, 2).toList(), r1.toList())
        val r2 = reader.readexactly(3)
        assertEquals(byteArrayOf(3, 4, 5).toList(), r2.toList())

        writer.write(byteArrayOf(6, 7, 8))
        writer.drain()
        val written = buf.consumeWrite()
        assertEquals(byteArrayOf(6, 7, 8).toList(), written.toList())
    }
}
