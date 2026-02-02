//
// MQTT5ReasonCodes.swift
// MqttQuicPlugin
//
// MQTT 5.0 Reason Codes. Matches MQTTD mqttd/reason_codes.py.
// Uses a struct so multiple names can share the same byte value (e.g. 0x00).
//

import Foundation

public struct MQTT5ReasonCode: Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    // Success (0x00 used in multiple packet types)
    public static let success = MQTT5ReasonCode(rawValue: 0x00)
    public static let normalDisconnection = MQTT5ReasonCode(rawValue: 0x00)
    public static let disconnectWithWillMessage = MQTT5ReasonCode(rawValue: 0x04)

    // CONNACK Reason Codes
    public static let unspecifiedError = MQTT5ReasonCode(rawValue: 0x80)
    public static let malformedPacket = MQTT5ReasonCode(rawValue: 0x81)
    public static let protocolError = MQTT5ReasonCode(rawValue: 0x82)
    public static let implementationSpecificError = MQTT5ReasonCode(rawValue: 0x83)
    public static let unsupportedProtocolVersion = MQTT5ReasonCode(rawValue: 0x84)
    public static let clientIdentifierNotValid = MQTT5ReasonCode(rawValue: 0x85)
    public static let badUserNameOrPassword = MQTT5ReasonCode(rawValue: 0x86)
    public static let notAuthorized = MQTT5ReasonCode(rawValue: 0x87)
    public static let serverUnavailable = MQTT5ReasonCode(rawValue: 0x88)
    public static let serverBusy = MQTT5ReasonCode(rawValue: 0x89)
    public static let banned = MQTT5ReasonCode(rawValue: 0x8A)
    public static let badAuthenticationMethod = MQTT5ReasonCode(rawValue: 0x8C)
    public static let topicNameInvalid = MQTT5ReasonCode(rawValue: 0x90)
    public static let packetTooLarge = MQTT5ReasonCode(rawValue: 0x95)
    public static let quotaExceeded = MQTT5ReasonCode(rawValue: 0x97)
    public static let payloadFormatInvalid = MQTT5ReasonCode(rawValue: 0x99)
    public static let retainNotSupported = MQTT5ReasonCode(rawValue: 0x9A)
    public static let qosNotSupported = MQTT5ReasonCode(rawValue: 0x9B)
    public static let useAnotherServer = MQTT5ReasonCode(rawValue: 0x9C)
    public static let serverMoved = MQTT5ReasonCode(rawValue: 0x9D)
    public static let connectionRateExceeded = MQTT5ReasonCode(rawValue: 0x9F)

    // PUBACK, PUBREC, PUBREL, PUBCOMP Reason Codes
    public static let noMatchingSubscribers = MQTT5ReasonCode(rawValue: 0x10)
    public static let unspecifiedErrorPub = MQTT5ReasonCode(rawValue: 0x80)
    public static let implementationSpecificErrorPub = MQTT5ReasonCode(rawValue: 0x83)
    public static let notAuthorizedPub = MQTT5ReasonCode(rawValue: 0x87)
    public static let topicNameInvalidPub = MQTT5ReasonCode(rawValue: 0x90)
    public static let packetIdentifierInUse = MQTT5ReasonCode(rawValue: 0x91)
    public static let quotaExceededPub = MQTT5ReasonCode(rawValue: 0x97)
    public static let payloadFormatInvalidPub = MQTT5ReasonCode(rawValue: 0x99)

    // SUBACK Reason Codes
    public static let grantedQoS0 = MQTT5ReasonCode(rawValue: 0x00)
    public static let grantedQoS1 = MQTT5ReasonCode(rawValue: 0x01)
    public static let grantedQoS2 = MQTT5ReasonCode(rawValue: 0x02)
    public static let unspecifiedErrorSub = MQTT5ReasonCode(rawValue: 0x80)
    public static let implementationSpecificErrorSub = MQTT5ReasonCode(rawValue: 0x83)
    public static let notAuthorizedSub = MQTT5ReasonCode(rawValue: 0x87)
    public static let topicFilterInvalid = MQTT5ReasonCode(rawValue: 0x8F)
    public static let packetIdentifierInUseSub = MQTT5ReasonCode(rawValue: 0x91)
    public static let quotaExceededSub = MQTT5ReasonCode(rawValue: 0x97)
    public static let sharedSubscriptionsNotSupported = MQTT5ReasonCode(rawValue: 0x9E)
    public static let subscriptionIdentifiersNotSupported = MQTT5ReasonCode(rawValue: 0xA1)
    public static let wildcardSubscriptionsNotSupported = MQTT5ReasonCode(rawValue: 0xA2)

    // UNSUBACK Reason Codes
    public static let successUnsub = MQTT5ReasonCode(rawValue: 0x00)
    public static let noSubscriptionExisted = MQTT5ReasonCode(rawValue: 0x11)
    public static let unspecifiedErrorUnsub = MQTT5ReasonCode(rawValue: 0x80)
    public static let implementationSpecificErrorUnsub = MQTT5ReasonCode(rawValue: 0x83)
    public static let notAuthorizedUnsub = MQTT5ReasonCode(rawValue: 0x87)
    public static let topicFilterInvalidUnsub = MQTT5ReasonCode(rawValue: 0x8F)
    public static let packetIdentifierInUseUnsub = MQTT5ReasonCode(rawValue: 0x91)

    // DISCONNECT Reason Codes
    public static let normalDisconnectionDisc = MQTT5ReasonCode(rawValue: 0x00)
    public static let disconnectWithWillMessageDisc = MQTT5ReasonCode(rawValue: 0x04)
    public static let unspecifiedErrorDisc = MQTT5ReasonCode(rawValue: 0x80)
    public static let malformedPacketDisc = MQTT5ReasonCode(rawValue: 0x81)
    public static let protocolErrorDisc = MQTT5ReasonCode(rawValue: 0x82)
    public static let implementationSpecificErrorDisc = MQTT5ReasonCode(rawValue: 0x83)
    public static let notAuthorizedDisc = MQTT5ReasonCode(rawValue: 0x87)
    public static let serverBusyDisc = MQTT5ReasonCode(rawValue: 0x89)
    public static let serverShuttingDown = MQTT5ReasonCode(rawValue: 0x8B)
    public static let badAuthenticationMethodDisc = MQTT5ReasonCode(rawValue: 0x8C)
    public static let keepAliveTimeout = MQTT5ReasonCode(rawValue: 0x8D)
    public static let sessionTakenOver = MQTT5ReasonCode(rawValue: 0x8E)
    public static let topicFilterInvalidDisc = MQTT5ReasonCode(rawValue: 0x8F)
    public static let topicNameInvalidDisc = MQTT5ReasonCode(rawValue: 0x90)
    public static let receiveMaximumExceeded = MQTT5ReasonCode(rawValue: 0x93)
    public static let topicAliasInvalid = MQTT5ReasonCode(rawValue: 0x94)
    public static let packetTooLargeDisc = MQTT5ReasonCode(rawValue: 0x95)
    public static let messageRateTooHigh = MQTT5ReasonCode(rawValue: 0x96)
    public static let quotaExceededDisc = MQTT5ReasonCode(rawValue: 0x97)
    public static let administrativeAction = MQTT5ReasonCode(rawValue: 0x98)
    public static let payloadFormatInvalidDisc = MQTT5ReasonCode(rawValue: 0x99)
    public static let retainNotSupportedDisc = MQTT5ReasonCode(rawValue: 0x9A)
    public static let qosNotSupportedDisc = MQTT5ReasonCode(rawValue: 0x9B)
    public static let useAnotherServerDisc = MQTT5ReasonCode(rawValue: 0x9C)
    public static let serverMovedDisc = MQTT5ReasonCode(rawValue: 0x9D)
    public static let sharedSubscriptionsNotSupportedDisc = MQTT5ReasonCode(rawValue: 0x9E)
    public static let connectionRateExceededDisc = MQTT5ReasonCode(rawValue: 0x9F)
    public static let maximumConnectTime = MQTT5ReasonCode(rawValue: 0xA0)
    public static let subscriptionIdentifiersNotSupportedDisc = MQTT5ReasonCode(rawValue: 0xA1)
    public static let wildcardSubscriptionsNotSupportedDisc = MQTT5ReasonCode(rawValue: 0xA2)
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
