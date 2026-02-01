package ai.annadata.mqttquic.mqtt

/**
 * MQTT 5.0 Reason Codes. Matches MQTTD mqttd/reason_codes.py.
 * MQTT 5.0 reuses byte values across packet types; we keep one constant per unique byte.
 * Context-specific aliases are provided as properties for semantic clarity.
 */
object MQTT5ReasonCode {
    // 0x00 - Success (CONNACK), Granted QoS 0 (SUBACK), Success (UNSUBACK), Normal disconnection (DISCONNECT)
    const val SUCCESS: Int = 0x00
    // 0x01 - Granted QoS 1 (SUBACK)
    const val GRANTED_QOS_1: Int = 0x01
    // 0x02 - Granted QoS 2 (SUBACK)
    const val GRANTED_QOS_2: Int = 0x02
    // 0x04 - Disconnect with will message
    const val DISCONNECT_WITH_WILL_MESSAGE: Int = 0x04
    // 0x10 - No matching subscribers (PUBACK/PUBREC/PUBREL/PUBCOMP)
    const val NO_MATCHING_SUBSCRIBERS: Int = 0x10
    // 0x11 - No subscription existed (UNSUBACK)
    const val NO_SUBSCRIPTION_EXISTED: Int = 0x11
    
    // CONNACK / generic errors (0x80+)
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
    const val SERVER_SHUTTING_DOWN: Int = 0x8B
    const val BAD_AUTHENTICATION_METHOD: Int = 0x8C
    const val KEEP_ALIVE_TIMEOUT: Int = 0x8D
    const val SESSION_TAKEN_OVER: Int = 0x8E
    const val TOPIC_FILTER_INVALID: Int = 0x8F
    const val TOPIC_NAME_INVALID: Int = 0x90
    const val PACKET_IDENTIFIER_IN_USE: Int = 0x91
    const val RECEIVE_MAXIMUM_EXCEEDED: Int = 0x93
    const val TOPIC_ALIAS_INVALID: Int = 0x94
    const val PACKET_TOO_LARGE: Int = 0x95
    const val MESSAGE_RATE_TOO_HIGH: Int = 0x96
    const val QUOTA_EXCEEDED: Int = 0x97
    const val ADMINISTRATIVE_ACTION: Int = 0x98
    const val PAYLOAD_FORMAT_INVALID: Int = 0x99
    const val RETAIN_NOT_SUPPORTED: Int = 0x9A
    const val QOS_NOT_SUPPORTED: Int = 0x9B
    const val USE_ANOTHER_SERVER: Int = 0x9C
    const val SERVER_MOVED: Int = 0x9D
    const val SHARED_SUBSCRIPTIONS_NOT_SUPPORTED: Int = 0x9E
    const val CONNECTION_RATE_EXCEEDED: Int = 0x9F
    const val MAXIMUM_CONNECT_TIME: Int = 0xA0
    const val SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED: Int = 0xA1
    const val WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED: Int = 0xA2
    
    // Context-specific aliases (all map to the same underlying values)
    // SUBACK aliases
    const val GRANTED_QOS_0: Int = SUCCESS  // 0x00
    
    // UNSUBACK aliases
    const val SUCCESS_UNSUB: Int = SUCCESS  // 0x00
    
    // DISCONNECT aliases
    const val NORMAL_DISCONNECTION: Int = SUCCESS  // 0x00
    const val NORMAL_DISCONNECTION_DISC: Int = SUCCESS  // 0x00
    const val DISCONNECT_WITH_WILL_MESSAGE_DISC: Int = DISCONNECT_WITH_WILL_MESSAGE  // 0x04
    const val UNSPECIFIED_ERROR_DISC: Int = UNSPECIFIED_ERROR  // 0x80
    const val MALFORMED_PACKET_DISC: Int = MALFORMED_PACKET  // 0x81
    const val PROTOCOL_ERROR_DISC: Int = PROTOCOL_ERROR  // 0x82
    const val IMPLEMENTATION_SPECIFIC_ERROR_DISC: Int = IMPLEMENTATION_SPECIFIC_ERROR  // 0x83
    const val NOT_AUTHORIZED_DISC: Int = NOT_AUTHORIZED  // 0x87
    const val SERVER_BUSY_DISC: Int = SERVER_BUSY  // 0x89
    const val BAD_AUTHENTICATION_METHOD_DISC: Int = BAD_AUTHENTICATION_METHOD  // 0x8C
    const val TOPIC_FILTER_INVALID_DISC: Int = TOPIC_FILTER_INVALID  // 0x8F
    const val TOPIC_NAME_INVALID_DISC: Int = TOPIC_NAME_INVALID  // 0x90
    const val PACKET_TOO_LARGE_DISC: Int = PACKET_TOO_LARGE  // 0x95
    const val QUOTA_EXCEEDED_DISC: Int = QUOTA_EXCEEDED  // 0x97
    const val PAYLOAD_FORMAT_INVALID_DISC: Int = PAYLOAD_FORMAT_INVALID  // 0x99
    const val RETAIN_NOT_SUPPORTED_DISC: Int = RETAIN_NOT_SUPPORTED  // 0x9A
    const val QOS_NOT_SUPPORTED_DISC: Int = QOS_NOT_SUPPORTED  // 0x9B
    const val USE_ANOTHER_SERVER_DISC: Int = USE_ANOTHER_SERVER  // 0x9C
    const val SERVER_MOVED_DISC: Int = SERVER_MOVED  // 0x9D
    const val SHARED_SUBSCRIPTIONS_NOT_SUPPORTED_DISC: Int = SHARED_SUBSCRIPTIONS_NOT_SUPPORTED  // 0x9E
    const val CONNECTION_RATE_EXCEEDED_DISC: Int = CONNECTION_RATE_EXCEEDED  // 0x9F
    const val SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED_DISC: Int = SUBSCRIPTION_IDENTIFIERS_NOT_SUPPORTED  // 0xA1
    const val WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED_DISC: Int = WILDCARD_SUBSCRIPTIONS_NOT_SUPPORTED  // 0xA2
    
    // PUBACK/PUBREC/PUBREL/PUBCOMP aliases
    const val UNSPECIFIED_ERROR_PUB: Int = UNSPECIFIED_ERROR  // 0x80
    const val IMPLEMENTATION_SPECIFIC_ERROR_PUB: Int = IMPLEMENTATION_SPECIFIC_ERROR  // 0x83
    const val NOT_AUTHORIZED_PUB: Int = NOT_AUTHORIZED  // 0x87
    const val TOPIC_NAME_INVALID_PUB: Int = TOPIC_NAME_INVALID  // 0x90
    const val QUOTA_EXCEEDED_PUB: Int = QUOTA_EXCEEDED  // 0x97
    const val PAYLOAD_FORMAT_INVALID_PUB: Int = PAYLOAD_FORMAT_INVALID  // 0x99
    
    // SUBACK aliases
    const val UNSPECIFIED_ERROR_SUB: Int = UNSPECIFIED_ERROR  // 0x80
    const val IMPLEMENTATION_SPECIFIC_ERROR_SUB: Int = IMPLEMENTATION_SPECIFIC_ERROR  // 0x83
    const val NOT_AUTHORIZED_SUB: Int = NOT_AUTHORIZED  // 0x87
    const val PACKET_IDENTIFIER_IN_USE_SUB: Int = PACKET_IDENTIFIER_IN_USE  // 0x91
    const val QUOTA_EXCEEDED_SUB: Int = QUOTA_EXCEEDED  // 0x97
    
    // UNSUBACK aliases
    const val UNSPECIFIED_ERROR_UNSUB: Int = UNSPECIFIED_ERROR  // 0x80
    const val IMPLEMENTATION_SPECIFIC_ERROR_UNSUB: Int = IMPLEMENTATION_SPECIFIC_ERROR  // 0x83
    const val NOT_AUTHORIZED_UNSUB: Int = NOT_AUTHORIZED  // 0x87
    const val TOPIC_FILTER_INVALID_UNSUB: Int = TOPIC_FILTER_INVALID  // 0x8F
    const val PACKET_IDENTIFIER_IN_USE_UNSUB: Int = PACKET_IDENTIFIER_IN_USE  // 0x91
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
