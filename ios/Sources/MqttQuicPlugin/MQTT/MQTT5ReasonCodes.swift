//
// MQTT5ReasonCodes.swift
// MqttQuicPlugin
//
// MQTT 5.0 Reason Codes. Matches MQTTD mqttd/reason_codes.py.
//

import Foundation

public enum MQTT5ReasonCode: UInt8 {
    // Success
    case success = 0x00
    case normalDisconnection = 0x00
    case disconnectWithWillMessage = 0x04
    
    // CONNACK Reason Codes
    case unspecifiedError = 0x80
    case malformedPacket = 0x81
    case protocolError = 0x82
    case implementationSpecificError = 0x83
    case unsupportedProtocolVersion = 0x84
    case clientIdentifierNotValid = 0x85
    case badUserNameOrPassword = 0x86
    case notAuthorized = 0x87
    case serverUnavailable = 0x88
    case serverBusy = 0x89
    case banned = 0x8A
    case badAuthenticationMethod = 0x8C
    case topicNameInvalid = 0x90
    case packetTooLarge = 0x95
    case quotaExceeded = 0x97
    case payloadFormatInvalid = 0x99
    case retainNotSupported = 0x9A
    case qosNotSupported = 0x9B
    case useAnotherServer = 0x9C
    case serverMoved = 0x9D
    case connectionRateExceeded = 0x9F
    
    // PUBACK, PUBREC, PUBREL, PUBCOMP Reason Codes
    case noMatchingSubscribers = 0x10
    case unspecifiedErrorPub = 0x80
    case implementationSpecificErrorPub = 0x83
    case notAuthorizedPub = 0x87
    case topicNameInvalidPub = 0x90
    case packetIdentifierInUse = 0x91
    case quotaExceededPub = 0x97
    case payloadFormatInvalidPub = 0x99
    
    // SUBACK Reason Codes
    case grantedQoS0 = 0x00
    case grantedQoS1 = 0x01
    case grantedQoS2 = 0x02
    case unspecifiedErrorSub = 0x80
    case implementationSpecificErrorSub = 0x83
    case notAuthorizedSub = 0x87
    case topicFilterInvalid = 0x8F
    case packetIdentifierInUseSub = 0x91
    case quotaExceededSub = 0x97
    case sharedSubscriptionsNotSupported = 0x9E
    case subscriptionIdentifiersNotSupported = 0xA1
    case wildcardSubscriptionsNotSupported = 0xA2
    
    // UNSUBACK Reason Codes
    case successUnsub = 0x00
    case noSubscriptionExisted = 0x11
    case unspecifiedErrorUnsub = 0x80
    case implementationSpecificErrorUnsub = 0x83
    case notAuthorizedUnsub = 0x87
    case topicFilterInvalidUnsub = 0x8F
    case packetIdentifierInUseUnsub = 0x91
    
    // DISCONNECT Reason Codes
    case normalDisconnectionDisc = 0x00
    case disconnectWithWillMessageDisc = 0x04
    case unspecifiedErrorDisc = 0x80
    case malformedPacketDisc = 0x81
    case protocolErrorDisc = 0x82
    case implementationSpecificErrorDisc = 0x83
    case notAuthorizedDisc = 0x87
    case serverBusyDisc = 0x89
    case serverShuttingDown = 0x8B
    case badAuthenticationMethodDisc = 0x8C
    case keepAliveTimeout = 0x8D
    case sessionTakenOver = 0x8E
    case topicFilterInvalidDisc = 0x8F
    case topicNameInvalidDisc = 0x90
    case receiveMaximumExceeded = 0x93
    case topicAliasInvalid = 0x94
    case packetTooLargeDisc = 0x95
    case messageRateTooHigh = 0x96
    case quotaExceededDisc = 0x97
    case administrativeAction = 0x98
    case payloadFormatInvalidDisc = 0x99
    case retainNotSupportedDisc = 0x9A
    case qosNotSupportedDisc = 0x9B
    case useAnotherServerDisc = 0x9C
    case serverMovedDisc = 0x9D
    case sharedSubscriptionsNotSupportedDisc = 0x9E
    case connectionRateExceededDisc = 0x9F
    case maximumConnectTime = 0xA0
    case subscriptionIdentifiersNotSupportedDisc = 0xA1
    case wildcardSubscriptionsNotSupportedDisc = 0xA2
}

// Compatibility mapping for MQTT 3.1.1 return codes
public let MQTT3_TO_MQTT5_REASON_CODE: [UInt8: MQTT5ReasonCode] = [
    0x00: .success,
    0x01: .unsupportedProtocolVersion,
    0x02: .clientIdentifierNotValid,
    0x03: .serverUnavailable,
    0x04: .badUserNameOrPassword,
    0x05: .notAuthorized,
]
