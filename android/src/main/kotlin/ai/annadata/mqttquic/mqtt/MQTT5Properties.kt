package ai.annadata.mqttquic.mqtt

import java.nio.charset.StandardCharsets

/**
 * MQTT 5.0 Property Types. Matches MQTTD mqttd/properties.py.
 */
object MQTT5PropertyType {
    const val PAYLOAD_FORMAT_INDICATOR: Byte = 0x01
    const val MESSAGE_EXPIRY_INTERVAL: Byte = 0x02
    const val CONTENT_TYPE: Byte = 0x03
    const val RESPONSE_TOPIC: Byte = 0x08
    const val CORRELATION_DATA: Byte = 0x09
    const val SUBSCRIPTION_IDENTIFIER: Byte = 0x0B
    const val SESSION_EXPIRY_INTERVAL: Byte = 0x11
    const val ASSIGNED_CLIENT_IDENTIFIER: Byte = 0x12
    const val SERVER_KEEP_ALIVE: Byte = 0x13
    const val AUTHENTICATION_METHOD: Byte = 0x15
    const val AUTHENTICATION_DATA: Byte = 0x16
    const val REQUEST_PROBLEM_INFORMATION: Byte = 0x17
    const val WILL_DELAY_INTERVAL: Byte = 0x18
    const val REQUEST_RESPONSE_INFORMATION: Byte = 0x19
    const val RESPONSE_INFORMATION: Byte = 0x1A
    const val SERVER_REFERENCE: Byte = 0x1C
    const val REASON_STRING: Byte = 0x1F
    const val RECEIVE_MAXIMUM: Byte = 0x21
    const val TOPIC_ALIAS_MAXIMUM: Byte = 0x22
    const val TOPIC_ALIAS: Byte = 0x23
    const val MAXIMUM_QOS: Byte = 0x24
    const val RETAIN_AVAILABLE: Byte = 0x25
    const val USER_PROPERTY: Byte = 0x26
    const val MAXIMUM_PACKET_SIZE: Byte = 0x27
    const val WILDCARD_SUBSCRIPTION_AVAILABLE: Byte = 0x28
    const val SUBSCRIPTION_IDENTIFIER_AVAILABLE: Byte = 0x29
    const val SHARED_SUBSCRIPTION_AVAILABLE: Byte = 0x2A
}

/**
 * MQTT 5.0 Properties encoder/decoder. Matches MQTTD mqttd/properties.py.
 */
object MQTT5PropertyEncoder {
    
    fun encodeProperties(props: Map<Int, Any>): ByteArray {
        val result = mutableListOf<Byte>()
        val sorted = props.toList().sortedBy { it.first }
        
        for ((propId, value) in sorted) {
            // Handle subscription identifier list
            if (propId == MQTT5PropertyType.SUBSCRIPTION_IDENTIFIER.toInt() && value is List<*>) {
                for (subId in value) {
                    result.add(propId.toByte())
                    result.addAll(encodeVariableByteInteger((subId as? Int) ?: 0).toList())
                }
                continue
            }
            
            result.add(propId.toByte())
            
            when (propId) {
                MQTT5PropertyType.PAYLOAD_FORMAT_INDICATOR.toInt() -> {
                    result.add(((value as? Int) ?: 0).toByte())
                }
                MQTT5PropertyType.MESSAGE_EXPIRY_INTERVAL.toInt(),
                MQTT5PropertyType.SESSION_EXPIRY_INTERVAL.toInt(),
                MQTT5PropertyType.WILL_DELAY_INTERVAL.toInt(),
                MQTT5PropertyType.MAXIMUM_PACKET_SIZE.toInt() -> {
                    val v = ((value as? Long) ?: 0L).toInt()
                    result.add((v shr 24).toByte())
                    result.add((v shr 16).toByte())
                    result.add((v shr 8).toByte())
                    result.add(v.toByte())
                }
                MQTT5PropertyType.CONTENT_TYPE.toInt(),
                MQTT5PropertyType.RESPONSE_TOPIC.toInt(),
                MQTT5PropertyType.ASSIGNED_CLIENT_IDENTIFIER.toInt(),
                MQTT5PropertyType.AUTHENTICATION_METHOD.toInt(),
                MQTT5PropertyType.RESPONSE_INFORMATION.toInt(),
                MQTT5PropertyType.SERVER_REFERENCE.toInt(),
                MQTT5PropertyType.REASON_STRING.toInt() -> {
                    result.addAll(encodeString((value as? String) ?: "").toList())
                }
                MQTT5PropertyType.CORRELATION_DATA.toInt(),
                MQTT5PropertyType.AUTHENTICATION_DATA.toInt() -> {
                    val data = (value as? ByteArray) ?: ByteArray(0)
                    result.add((data.size shr 8).toByte())
                    result.add((data.size and 0xFF).toByte())
                    result.addAll(data.toList())
                }
                MQTT5PropertyType.SUBSCRIPTION_IDENTIFIER.toInt() -> {
                    result.addAll(encodeVariableByteInteger((value as? Int) ?: 0).toList())
                }
                MQTT5PropertyType.SERVER_KEEP_ALIVE.toInt(),
                MQTT5PropertyType.RECEIVE_MAXIMUM.toInt(),
                MQTT5PropertyType.TOPIC_ALIAS_MAXIMUM.toInt(),
                MQTT5PropertyType.TOPIC_ALIAS.toInt() -> {
                    val v = ((value as? Int) ?: 0).toInt()
                    result.add((v shr 8).toByte())
                    result.add((v and 0xFF).toByte())
                }
                MQTT5PropertyType.MAXIMUM_QOS.toInt(),
                MQTT5PropertyType.RETAIN_AVAILABLE.toInt(),
                MQTT5PropertyType.REQUEST_PROBLEM_INFORMATION.toInt(),
                MQTT5PropertyType.REQUEST_RESPONSE_INFORMATION.toInt(),
                MQTT5PropertyType.WILDCARD_SUBSCRIPTION_AVAILABLE.toInt(),
                MQTT5PropertyType.SUBSCRIPTION_IDENTIFIER_AVAILABLE.toInt(),
                MQTT5PropertyType.SHARED_SUBSCRIPTION_AVAILABLE.toInt() -> {
                    result.add(((value as? Int) ?: 0).toByte())
                }
                MQTT5PropertyType.USER_PROPERTY.toInt() -> {
                    if (value is Pair<*, *>) {
                        result.addAll(encodeString((value.first as? String) ?: "").toList())
                        result.addAll(encodeString((value.second as? String) ?: "").toList())
                    } else {
                        throw IllegalArgumentException("USER_PROPERTY must be Pair<String, String>")
                    }
                }
                else -> throw IllegalArgumentException("Unknown property type: $propId")
            }
        }
        
        return result.toByteArray()
    }
    
    fun decodeProperties(data: ByteArray, offset: Int = 0): Pair<Map<Int, Any>, Int> {
        val props = mutableMapOf<Int, Any>()
        var pos = offset
        
        while (pos < data.size) {
            val propId = data[pos].toInt() and 0xFF
            pos++
            
            when (propId) {
                MQTT5PropertyType.PAYLOAD_FORMAT_INDICATOR.toInt() -> {
                    props[propId] = data[pos].toInt() and 0xFF
                    pos++
                }
                MQTT5PropertyType.MESSAGE_EXPIRY_INTERVAL.toInt(),
                MQTT5PropertyType.SESSION_EXPIRY_INTERVAL.toInt(),
                MQTT5PropertyType.WILL_DELAY_INTERVAL.toInt(),
                MQTT5PropertyType.MAXIMUM_PACKET_SIZE.toInt() -> {
                    val v = ((data[pos].toInt() and 0xFF) shl 24) or
                            ((data[pos + 1].toInt() and 0xFF) shl 16) or
                            ((data[pos + 2].toInt() and 0xFF) shl 8) or
                            (data[pos + 3].toInt() and 0xFF)
                    props[propId] = v
                    pos += 4
                }
                MQTT5PropertyType.CONTENT_TYPE.toInt(),
                MQTT5PropertyType.RESPONSE_TOPIC.toInt(),
                MQTT5PropertyType.ASSIGNED_CLIENT_IDENTIFIER.toInt(),
                MQTT5PropertyType.AUTHENTICATION_METHOD.toInt(),
                MQTT5PropertyType.RESPONSE_INFORMATION.toInt(),
                MQTT5PropertyType.SERVER_REFERENCE.toInt(),
                MQTT5PropertyType.REASON_STRING.toInt() -> {
                    val (s, next) = decodeString(data, pos)
                    props[propId] = s
                    pos = next
                }
                MQTT5PropertyType.CORRELATION_DATA.toInt(),
                MQTT5PropertyType.AUTHENTICATION_DATA.toInt() -> {
                    val len = ((data[pos].toInt() and 0xFF) shl 8) or (data[pos + 1].toInt() and 0xFF)
                    pos += 2
                    props[propId] = data.copyOfRange(pos, pos + len)
                    pos += len
                }
                MQTT5PropertyType.SUBSCRIPTION_IDENTIFIER.toInt() -> {
                    val (v, consumed) = decodeVariableByteInteger(data, pos)
                    val list = (props[propId] as? MutableList<Int>) ?: mutableListOf()
                    list.add(v)
                    props[propId] = list
                    pos += consumed
                }
                MQTT5PropertyType.SERVER_KEEP_ALIVE.toInt(),
                MQTT5PropertyType.RECEIVE_MAXIMUM.toInt(),
                MQTT5PropertyType.TOPIC_ALIAS_MAXIMUM.toInt(),
                MQTT5PropertyType.TOPIC_ALIAS.toInt() -> {
                    val v = ((data[pos].toInt() and 0xFF) shl 8) or (data[pos + 1].toInt() and 0xFF)
                    props[propId] = v
                    pos += 2
                }
                MQTT5PropertyType.MAXIMUM_QOS.toInt(),
                MQTT5PropertyType.RETAIN_AVAILABLE.toInt(),
                MQTT5PropertyType.REQUEST_PROBLEM_INFORMATION.toInt(),
                MQTT5PropertyType.REQUEST_RESPONSE_INFORMATION.toInt(),
                MQTT5PropertyType.WILDCARD_SUBSCRIPTION_AVAILABLE.toInt(),
                MQTT5PropertyType.SUBSCRIPTION_IDENTIFIER_AVAILABLE.toInt(),
                MQTT5PropertyType.SHARED_SUBSCRIPTION_AVAILABLE.toInt() -> {
                    props[propId] = data[pos].toInt() and 0xFF
                    pos++
                }
                MQTT5PropertyType.USER_PROPERTY.toInt() -> {
                    val (name, next1) = decodeString(data, pos)
                    pos = next1
                    val (value, next2) = decodeString(data, pos)
                    pos = next2
                    val list = (props[propId] as? MutableList<Pair<String, String>>) ?: mutableListOf()
                    list.add(name to value)
                    props[propId] = list
                }
                else -> break // Unknown property - skip
            }
        }
        
        return props to (pos - offset)
    }
    
    private fun encodeString(s: String): ByteArray {
        val utf8 = s.toByteArray(StandardCharsets.UTF_8)
        if (utf8.size > 0xFFFF) throw IllegalArgumentException("String too long")
        return byteArrayOf((utf8.size shr 8).toByte(), (utf8.size and 0xFF).toByte()) + utf8
    }
    
    private fun decodeString(data: ByteArray, offset: Int): Pair<String, Int> {
        if (offset + 2 > data.size) throw IllegalArgumentException("Insufficient data for string length")
        val len = ((data[offset].toInt() and 0xFF) shl 8) or (data[offset + 1].toInt() and 0xFF)
        val start = offset + 2
        if (start + len > data.size) throw IllegalArgumentException("Insufficient data for string content")
        val sub = data.copyOfRange(start, start + len)
        val s = String(sub, StandardCharsets.UTF_8)
        return s to (start + len)
    }
    
    private fun encodeVariableByteInteger(value: Int): ByteArray {
        if (value < 0 || value > 268_435_455) throw IllegalArgumentException("Invalid variable byte integer: $value")
        val enc = mutableListOf<Byte>()
        var n = value
        do {
            var b = (n % 128).toByte()
            n /= 128
            if (n > 0) b = (b.toInt() or 0x80).toByte()
            enc.add(b)
        } while (n > 0)
        return enc.toByteArray()
    }
    
    private fun decodeVariableByteInteger(data: ByteArray, offset: Int): Pair<Int, Int> {
        var mul = 1
        var value = 0
        var i = offset
        repeat(4) {
            if (i >= data.size) throw IllegalArgumentException("Insufficient data for variable byte integer")
            val b = data[i].toInt() and 0xFF
            value += (b and 0x7F) * mul
            i++
            if ((b and 0x80) == 0) return@repeat
            mul *= 128
        }
        return value to (i - offset)
    }
}
