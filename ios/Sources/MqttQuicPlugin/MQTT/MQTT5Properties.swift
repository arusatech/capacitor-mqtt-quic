//
// MQTT5Properties.swift
// MqttQuicPlugin
//
// MQTT 5.0 Properties encoder/decoder. Matches MQTTD mqttd/properties.py.
//

import Foundation

public enum MQTT5PropertyType: UInt8 {
    case payloadFormatIndicator = 0x01
    case messageExpiryInterval = 0x02
    case contentType = 0x03
    case responseTopic = 0x08
    case correlationData = 0x09
    case subscriptionIdentifier = 0x0B
    case sessionExpiryInterval = 0x11
    case assignedClientIdentifier = 0x12
    case serverKeepAlive = 0x13
    case authenticationMethod = 0x15
    case authenticationData = 0x16
    case requestProblemInformation = 0x17
    case willDelayInterval = 0x18
    case requestResponseInformation = 0x19
    case responseInformation = 0x1A
    case serverReference = 0x1C
    case reasonString = 0x1F
    case receiveMaximum = 0x21
    case topicAliasMaximum = 0x22
    case topicAlias = 0x23
    case maximumQoS = 0x24
    case retainAvailable = 0x25
    case userProperty = 0x26
    case maximumPacketSize = 0x27
    case wildcardSubscriptionAvailable = 0x28
    case subscriptionIdentifierAvailable = 0x29
    case sharedSubscriptionAvailable = 0x2A
}

public struct MQTT5Properties {
    public var properties: [UInt8: Any] = [:]
    
    public init() {}
    
    public mutating func set(_ type: MQTT5PropertyType, _ value: Any) {
        properties[type.rawValue] = value
    }
    
    public func get(_ type: MQTT5PropertyType) -> Any? {
        return properties[type.rawValue]
    }
}

public final class MQTT5PropertyEncoder {
    
    public static func encodeProperties(_ props: [UInt8: Any]) throws -> Data {
        var result = Data()
        let sorted = props.sorted { $0.key < $1.key }
        
        for (propId, value) in sorted {
            // Handle subscription identifier list specially
            if propId == MQTT5PropertyType.subscriptionIdentifier.rawValue, let list = value as? [Int] {
                for subId in list {
                    result.append(propId)
                    result.append(contentsOf: try encodeVariableByteInteger(subId))
                }
                continue
            }
            
            result.append(propId)
            
            switch propId {
            case MQTT5PropertyType.payloadFormatIndicator.rawValue:
                result.append(UInt8((value as? Int ?? 0) & 0xFF))
                
            case MQTT5PropertyType.messageExpiryInterval.rawValue,
                 MQTT5PropertyType.sessionExpiryInterval.rawValue,
                 MQTT5PropertyType.willDelayInterval.rawValue,
                 MQTT5PropertyType.maximumPacketSize.rawValue:
                let v = (value as? UInt32 ?? 0)
                result.append(UInt8((v >> 24) & 0xFF))
                result.append(UInt8((v >> 16) & 0xFF))
                result.append(UInt8((v >> 8) & 0xFF))
                result.append(UInt8(v & 0xFF))
                
            case MQTT5PropertyType.contentType.rawValue,
                 MQTT5PropertyType.responseTopic.rawValue,
                 MQTT5PropertyType.assignedClientIdentifier.rawValue,
                 MQTT5PropertyType.authenticationMethod.rawValue,
                 MQTT5PropertyType.responseInformation.rawValue,
                 MQTT5PropertyType.serverReference.rawValue,
                 MQTT5PropertyType.reasonString.rawValue:
                result.append(try encodeString(value as? String ?? ""))
                
            case MQTT5PropertyType.correlationData.rawValue,
                 MQTT5PropertyType.authenticationData.rawValue:
                let data = value as? Data ?? Data()
                result.append(UInt8((data.count >> 8) & 0xFF))
                result.append(UInt8(data.count & 0xFF))
                result.append(data)
                
            case MQTT5PropertyType.subscriptionIdentifier.rawValue:
                result.append(contentsOf: try encodeVariableByteInteger(value as? Int ?? 0))
                
            case MQTT5PropertyType.serverKeepAlive.rawValue,
                 MQTT5PropertyType.receiveMaximum.rawValue,
                 MQTT5PropertyType.topicAliasMaximum.rawValue,
                 MQTT5PropertyType.topicAlias.rawValue:
                let v = (value as? UInt16 ?? 0)
                result.append(UInt8((v >> 8) & 0xFF))
                result.append(UInt8(v & 0xFF))
                
            case MQTT5PropertyType.maximumQoS.rawValue,
                 MQTT5PropertyType.retainAvailable.rawValue,
                 MQTT5PropertyType.requestProblemInformation.rawValue,
                 MQTT5PropertyType.requestResponseInformation.rawValue,
                 MQTT5PropertyType.wildcardSubscriptionAvailable.rawValue,
                 MQTT5PropertyType.subscriptionIdentifierAvailable.rawValue,
                 MQTT5PropertyType.sharedSubscriptionAvailable.rawValue:
                result.append(UInt8((value as? Int ?? 0) & 0xFF))
                
            case MQTT5PropertyType.userProperty.rawValue:
                if let pair = value as? (String, String) {
                    result.append(try encodeString(pair.0))
                    result.append(try encodeString(pair.1))
                } else {
                    throw MQTTProtocolError.insufficientData("USER_PROPERTY must be (String, String)")
                }
                
            default:
                throw MQTTProtocolError.insufficientData("Unknown property type: \(propId)")
            }
        }
        
        return result
    }
    
    public static func decodeProperties(_ data: Data, offset: Int = 0) throws -> ([UInt8: Any], Int) {
        var props: [UInt8: Any] = [:]
        var pos = offset
        
        while pos < data.count {
            let propId = data[pos]
            pos += 1
            
            switch propId {
            case MQTT5PropertyType.payloadFormatIndicator.rawValue:
                props[propId] = Int(data[pos] & 0xFF)
                pos += 1
                
            case MQTT5PropertyType.messageExpiryInterval.rawValue,
                 MQTT5PropertyType.sessionExpiryInterval.rawValue,
                 MQTT5PropertyType.willDelayInterval.rawValue,
                 MQTT5PropertyType.maximumPacketSize.rawValue:
                let v = (UInt32(data[pos] & 0xFF) << 24) |
                        (UInt32(data[pos + 1] & 0xFF) << 16) |
                        (UInt32(data[pos + 2] & 0xFF) << 8) |
                        UInt32(data[pos + 3] & 0xFF)
                props[propId] = v
                pos += 4
                
            case MQTT5PropertyType.contentType.rawValue,
                 MQTT5PropertyType.responseTopic.rawValue,
                 MQTT5PropertyType.assignedClientIdentifier.rawValue,
                 MQTT5PropertyType.authenticationMethod.rawValue,
                 MQTT5PropertyType.responseInformation.rawValue,
                 MQTT5PropertyType.serverReference.rawValue,
                 MQTT5PropertyType.reasonString.rawValue:
                let (s, next) = try decodeString(data, offset: pos)
                props[propId] = s
                pos = next
                
            case MQTT5PropertyType.correlationData.rawValue,
                 MQTT5PropertyType.authenticationData.rawValue:
                let len = (Int(data[pos] & 0xFF) << 8) | Int(data[pos + 1] & 0xFF)
                pos += 2
                props[propId] = data.subdata(in: pos..<(pos + len))
                pos += len
                
            case MQTT5PropertyType.subscriptionIdentifier.rawValue:
                let (v, consumed) = try decodeVariableByteInteger(data, offset: pos)
                if props[propId] == nil {
                    props[propId] = [v]
                } else if var list = props[propId] as? [Int] {
                    list.append(v)
                    props[propId] = list
                } else {
                    props[propId] = [v]
                }
                pos += consumed
                
            case MQTT5PropertyType.serverKeepAlive.rawValue,
                 MQTT5PropertyType.receiveMaximum.rawValue,
                 MQTT5PropertyType.topicAliasMaximum.rawValue,
                 MQTT5PropertyType.topicAlias.rawValue:
                let v = (UInt16(data[pos] & 0xFF) << 8) | UInt16(data[pos + 1] & 0xFF)
                props[propId] = v
                pos += 2
                
            case MQTT5PropertyType.maximumQoS.rawValue,
                 MQTT5PropertyType.retainAvailable.rawValue,
                 MQTT5PropertyType.requestProblemInformation.rawValue,
                 MQTT5PropertyType.requestResponseInformation.rawValue,
                 MQTT5PropertyType.wildcardSubscriptionAvailable.rawValue,
                 MQTT5PropertyType.subscriptionIdentifierAvailable.rawValue,
                 MQTT5PropertyType.sharedSubscriptionAvailable.rawValue:
                props[propId] = Int(data[pos] & 0xFF)
                pos += 1
                
            case MQTT5PropertyType.userProperty.rawValue:
                let (name, next1) = try decodeString(data, offset: pos)
                pos = next1
                let (value, next2) = try decodeString(data, offset: pos)
                pos = next2
                if props[propId] == nil {
                    props[propId] = [(name, value)]
                } else if var list = props[propId] as? [(String, String)] {
                    list.append((name, value))
                    props[propId] = list
                } else {
                    props[propId] = [(name, value)]
                }
                
            default:
                // Unknown property - skip (per spec)
                break
            }
        }
        
        return (props, pos - offset)
    }
    
    private static func encodeString(_ s: String) throws -> Data {
        guard let utf8 = s.data(using: .utf8) else { throw MQTTProtocolError.invalidUTF8 }
        if utf8.count > 0xFFFF { throw MQTTProtocolError.insufficientData("string too long") }
        var out = Data()
        out.append(UInt8((utf8.count >> 8) & 0xFF))
        out.append(UInt8(utf8.count & 0xFF))
        out.append(utf8)
        return out
    }
    
    private static func decodeString(_ data: Data, offset: Int) throws -> (String, Int) {
        if offset + 2 > data.count { throw MQTTProtocolError.insufficientData("string length") }
        let len = (Int(data[offset] & 0xFF) << 8) | Int(data[offset + 1] & 0xFF)
        let start = offset + 2
        if start + len > data.count { throw MQTTProtocolError.insufficientData("string content") }
        let sub = data.subdata(in: start..<(start + len))
        guard let s = String(data: sub, encoding: .utf8) else { throw MQTTProtocolError.invalidUTF8 }
        return (s, start + len)
    }
    
    private static func encodeVariableByteInteger(_ value: Int) throws -> Data {
        if value < 0 || value > 268_435_455 { throw MQTTProtocolError.invalidRemainingLength(value) }
        var enc: [UInt8] = []
        var n = value
        repeat {
            var b = UInt8(n % 128)
            n /= 128
            if n > 0 { b |= 0x80 }
            enc.append(b)
        } while n > 0
        return Data(enc)
    }
    
    private static func decodeVariableByteInteger(_ data: Data, offset: Int) throws -> (Int, Int) {
        var mul = 1
        var val = 0
        var i = offset
        for _ in 0..<4 {
            if i >= data.count { throw MQTTProtocolError.insufficientData("variable byte integer") }
            let b = data[i]
            val += Int(b & 0x7F) * mul
            i += 1
            if (b & 0x80) == 0 { break }
            mul *= 128
        }
        return (val, i - offset)
    }
}
