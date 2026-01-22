package ai.annadata.mqttquic.mqtt

/**
 * MQTT 5.0 Reason Codes. Matches MQTTD mqttd/reason_codes.py.
 */
object MQTT5ReasonCode {
    // Success
    const val SUCCESS: Int = 0x00
    const val NORMAL_DISCONNECTION: Int = 0x00
    const val DISCONNECT_WITH_WILL_MESSAGE: Int = 0x04
    
    // CONNACK Reason Codes
    const val UNSPECIFIED_ERROR: Int = 0x80
    const val MALFORMED_PACKET: Int = 0x81
    const val PROTOCOL_ERROR: Int = 0x82
    const val IMPLEMENTATION_SPECIFIC_ERROR: Int = 0x83
    const val UNSUPPORTED_PROTOCOL_VERSION: Int = 0x84
    const val CLIENT_IDENTIFIER_NOT_VALID: Int = 0x85
    const val BAD_USER_NAME_OR_PASSWORD: Int = 0x86
    const val NOT_AUTHORIZED: Int = 0x87
    const val SERVER_UNAVAILABLE: Int = 0x88
    const val SERVER_BUSY: Int = 0x89
    const val BANNED: Int = 0x8A
    const val BAD_AUTHENTICATION_METHOD: Int = 0x8C
    const val TOPIC_NAME_INVALID: Int = 0x90
    const val PACKET_TOO_LARGE: Int = 0x95
    const val QUOTA_EXCEEDED: Int = 0x97
    const val PAYLOAD_FORMAT_INVALID: Int = 0x99
    const val RETAIN_NOT_SUPPORTED: Int = 0x9A
    const val QOS_NOT_SUPPORTED: Int = 0x9B
    const val USE_ANOTHER_SERVER: Int = 0x9C
    const val SERVER_MOVED: Int = 0x9D
    const val CONNECTION_RATE_EXCEEDED: Int = 0x9F
    
    // PUBACK, PUBREC, PUBREL, PUBCOMP Reason Codes
    const val NO_MATCHING_SUBSCRIBERS: Int = 0x10
    const val UNSPECIFIED_ERROR_PUB: Int = 0x80
    const val IMPLEMENTATION_SPECIFIC_ERROR_PUB: Int = 0x83
    const val NOT_AUTHORIZED_PUB: Int = 0x87
    const val TOPIC_NAME_INVALID_PUB: Int = 0x90
    const val PACKET_IDENTIFIER_IN_USE: Int = 0x91
    const val QUOTA_EXCEEDED_PUB: Int = 0x97
    const val PAYLOAD_FORMAT_INVALID_PUB: Int = 0x99
    
    // SUBACK Reason Codes
    const val GRANTED_QOS_0: Int = 0x00
    const val GRANTED_QOS_1: Int = 0x01
    const val GRANTED_QOS_2: Int = 0x02
    const val UNSPECIFIED_ERROR_SUB: Int = 0x80
    const val IMPLEMENTATION_SPECIFIC_ERROR_SUB: Int = 0x83
    const val NOT_AUTHORIZED_SUB: Int = 0x87
    const val TOPIC_FILTER_INVALID: Int = 0x8F
    const val PACKET_IDENTIFIER_IN_USE_SUB: Int = 0x91
    const val QUOTA_EXCEEDED_SUB: Int = 0x97
    const val SHARED_SUBSCRIPTIONS_NOT_SUPPORTED: Int = 0x9E
    const val SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED: Int = 0xA1
    const val WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED: Int = 0xA2
    
    // UNSUBACK Reason Codes
    const val SUCCESS_UNSUB: Int = 0x00
    const val NO_SUBSCRIPTION_EXISTED: Int = 0x11
    const val UNSPECIFIED_ERROR_UNSUB: Int = 0x80
    const val IMPLEMENTATION_SPECIFIC_ERROR_UNSUB: Int = 0x83
    const val NOT_AUTHORIZED_UNSUB: Int = 0x87
    const val TOPIC_FILTER_INVALID_UNSUB: Int = 0x8F
    const val PACKET_IDENTIFIER_IN_USE_UNSUB: Int = 0x91
    
    // DISCONNECT Reason Codes
    const val NORMAL_DISCONNECTION_DISC: Int = 0x00
    const val DISCONNECT_WITH_WILL_MESSAGE_DISC: Int = 0x04
    const val UNSPECIFIED_ERROR_DISC: Int = 0x80
    const val MALFORMED_PACKET_DISC: Int = 0x81
    const val PROTOCOL_ERROR_DISC: Int = 0x82
    const val IMPLEMENTATION_SPECIFIC_ERROR_DISC: Int = 0x83
    const val NOT_AUTHORIZED_DISC: Int = 0x87
    const val SERVER_BUSY_DISC: Int = 0x89
    const val SERVER_SHUTTING_DOWN: Int = 0x8B
    const val BAD_AUTHENTICATION_METHOD_DISC: Int = 0x8C
    const val KEEP_ALIVE_TIMEOUT: Int = 0x8D
    const val SESSION_TAKEN_OVER: Int = 0x8E
    const val TOPIC_FILTER_INVALID_DISC: Int = 0x8F
    const val TOPIC_NAME_INVALID_DISC: Int = 0x90
    const val RECEIVE_MAXIMUM_EXCEEDED: Int = 0x93
    const val TOPIC_ALIAS_INVALID: Int = 0x94
    const val PACKET_TOO_LARGE_DISC: Int = 0x95
    const val MESSAGE_RATE_TOO_HIGH: Int = 0x96
    const val QUOTA_EXCEEDED_DISC: Int = 0x97
    const val ADMINISTRATIVE_ACTION: Int = 0x98
    const val PAYLOAD_FORMAT_INVALID_DISC: Int = 0x99
    const val RETAIN_NOT_SUPPORTED_DISC: Int = 0x9A
    const val QOS_NOT_SUPPORTED_DISC: Int = 0x9B
    const val USE_ANOTHER_SERVER_DISC: Int = 0x9C
    const val SERVER_MOVED_DISC: Int = 0x9D
    const val SHARED_SUBSCRIPTIONS_NOT_SUPPORTED_DISC: Int = 0x9E
    const val CONNECTION_RATE_EXCEEDED_DISC: Int = 0x9F
    const val MAXIMUM_CONNECT_TIME: Int = 0xA0
    const val SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED_DISC: Int = 0xA1
    const val WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED_DISC: Int = 0xA2
}

// Compatibility mapping for MQTT 3.1.1 return codes
val MQTT3_TO_MQTT5_REASON_CODE = mapOf(
    0x00 to MQTT5ReasonCode.SUCCESS,
    0x01 to MQTT5ReasonCode.UNSUPPORTED_PROTOCOL_VERSION,
    0x02 to MQTT5ReasonCode.CLIENT_IDENTIFIER_NOT_VALID,
    0x03 to MQTT5ReasonCode.SERVER_UNAVAILABLE,
    0x04 to MQTT5ReasonCode.BAD_USER_NAME_OR_PASSWORD,
    0x05 to MQTT5ReasonCode.NOT_AUTHORIZED,
)
