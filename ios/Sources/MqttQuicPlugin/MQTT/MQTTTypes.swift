//
// MQTTTypes.swift
// MqttQuicPlugin
//
// MQTT packet types and constants. Matches MQTTD protocol.py / protocol_v5.py.
//

import Foundation

/// MQTT 3.1.1 / 5.0 message types (fixed header first nibble)
public enum MQTTMessageType: UInt8 {
    case CONNECT = 0x10
    case CONNACK = 0x20
    case PUBLISH = 0x30
    case PUBACK = 0x40
    case PUBREC = 0x50
    case PUBREL = 0x62
    case PUBCOMP = 0x70
    case SUBSCRIBE = 0x82
    case SUBACK = 0x90
    case UNSUBSCRIBE = 0xA2
    case UNSUBACK = 0xB0
    case PINGREQ = 0xC0
    case PINGRESP = 0xD0
    case DISCONNECT = 0xE0
}

/// CONNECT flags
public struct MQTTConnectFlags {
    public static let username: UInt8 = 0x80
    public static let password: UInt8 = 0x40
    public static let willRetain: UInt8 = 0x20
    public static let willQoS1: UInt8 = 0x08
    public static let willQoS2: UInt8 = 0x18
    public static let willFlag: UInt8 = 0x04
    public static let cleanSession: UInt8 = 0x02
    public static let reserved: UInt8 = 0x01
}

/// CONNACK return codes (MQTT 3.1.1)
public enum MQTTConnAckCode: UInt8 {
    case accepted = 0x00
    case unacceptableProtocol = 0x01
    case identifierRejected = 0x02
    case serverUnavailable = 0x03
    case badUsernamePassword = 0x04
    case notAuthorized = 0x05
}

/// Protocol levels
public struct MQTTProtocolLevel {
    public static let v311: UInt8 = 0x04
    public static let v5: UInt8 = 0x05
}
