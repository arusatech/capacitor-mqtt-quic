package ai.annadata.mqttquic.mqtt

/**
 * MQTT packet types and constants. Matches MQTTD protocol.py / protocol_v5.py.
 */

object MQTTMessageType {
    const val CONNECT: Byte = 0x10.toByte()
    const val CONNACK: Byte = 0x20.toByte()
    const val PUBLISH: Byte = 0x30.toByte()
    const val PUBACK: Byte = 0x40.toByte()
    const val PUBREC: Byte = 0x50.toByte()
    const val PUBREL: Byte = 0x62.toByte()
    const val PUBCOMP: Byte = 0x70.toByte()
    const val SUBSCRIBE: Byte = 0x82.toByte()
    const val SUBACK: Byte = 0x90.toByte()
    const val UNSUBSCRIBE: Byte = 0xA2.toByte()
    const val UNSUBACK: Byte = 0xB0.toByte()
    const val PINGREQ: Byte = 0xC0.toByte()
    const val PINGRESP: Byte = 0xD0.toByte()
    const val DISCONNECT: Byte = 0xE0.toByte()
    const val AUTH: Byte = 0xF0.toByte()
}

object MQTTConnectFlags {
    const val USERNAME: Int = 0x80
    const val PASSWORD: Int = 0x40
    const val WILL_RETAIN: Int = 0x20
    const val WILL_QOS1: Int = 0x08
    const val WILL_QOS2: Int = 0x18
    const val WILL_FLAG: Int = 0x04
    const val CLEAN_SESSION: Int = 0x02
    const val RESERVED: Int = 0x01
}

object MQTTConnAckCode {
    const val ACCEPTED: Int = 0x00
    const val UNACCEPTABLE_PROTOCOL: Int = 0x01
    const val IDENTIFIER_REJECTED: Int = 0x02
    const val SERVER_UNAVAILABLE: Int = 0x03
    const val BAD_USERNAME_PASSWORD: Int = 0x04
    const val NOT_AUTHORIZED: Int = 0x05
}

object MQTTProtocolLevel {
    const val V311: Byte = 0x04
    const val V5: Byte = 0x05
}
