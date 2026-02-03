//
// MQTT5Protocol.swift
// MqttQuicPlugin
//
// MQTT 5.0 Protocol implementation. Matches MQTTD mqttd/protocol_v5.py.
//

import Foundation

public final class MQTT5Protocol {
    
    public static func buildConnectV5(
        clientId: String,
        username: String? = nil,
        password: String? = nil,
        keepalive: UInt16 = 20,
        cleanStart: Bool = true,
        sessionExpiryInterval: UInt32? = nil,
        receiveMaximum: UInt16? = nil,
        maximumPacketSize: UInt32? = nil,
        topicAliasMaximum: UInt16? = nil,
        requestResponseInformation: UInt8? = nil,
        requestProblemInformation: UInt8? = nil,
        authenticationMethod: String? = nil,
        authenticationData: Data? = nil,
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var variableHeader = Data()
        variableHeader.append(try MQTTProtocol.encodeString("MQTT"))
        variableHeader.append(MQTTProtocolLevel.v5)
        
        var flags: UInt8 = 0
        if cleanStart { flags |= 0x02 }
        if username != nil { flags |= MQTTConnectFlags.username }
        if password != nil { flags |= MQTTConnectFlags.password }
        variableHeader.append(flags)
        variableHeader.append(UInt8((keepalive >> 8) & 0xFF))
        variableHeader.append(UInt8(keepalive & 0xFF))
        
        var connectProps: [UInt8: Any] = [:]
        if let sei = sessionExpiryInterval {
            connectProps[MQTT5PropertyType.sessionExpiryInterval.rawValue] = sei
        }
        if let rm = receiveMaximum {
            connectProps[MQTT5PropertyType.receiveMaximum.rawValue] = rm
        }
        if let mps = maximumPacketSize {
            connectProps[MQTT5PropertyType.maximumPacketSize.rawValue] = mps
        }
        if let tam = topicAliasMaximum {
            connectProps[MQTT5PropertyType.topicAliasMaximum.rawValue] = tam
        }
        if let rri = requestResponseInformation {
            connectProps[MQTT5PropertyType.requestResponseInformation.rawValue] = rri
        }
        if let rpi = requestProblemInformation {
            connectProps[MQTT5PropertyType.requestProblemInformation.rawValue] = rpi
        }
        if let am = authenticationMethod {
            connectProps[MQTT5PropertyType.authenticationMethod.rawValue] = am
        }
        if let ad = authenticationData {
            connectProps[MQTT5PropertyType.authenticationData.rawValue] = ad
        }
        if let props = properties {
            connectProps.merge(props) { (_, new) in new }
        }
        
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(connectProps)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        variableHeader.append(contentsOf: propsLen)
        variableHeader.append(propsBytes)
        
        var payload = Data()
        payload.append(try MQTTProtocol.encodeString(clientId))
        payload.append(0x00) // Will Properties length = 0 (no will for now)
        if let u = username { payload.append(try MQTTProtocol.encodeString(u)) }
        if let p = password { payload.append(try MQTTProtocol.encodeString(p)) }
        
        let remLen = variableHeader.count + payload.count
        var fixed = Data()
        fixed.append(MQTTMessageType.CONNECT.rawValue)
        fixed.append(contentsOf: try MQTTProtocol.encodeRemainingLength(remLen))
        
        var out = Data()
        out.append(fixed)
        out.append(variableHeader)
        out.append(payload)
        return out
    }
    
    public static func buildConnackV5(
        reasonCode: MQTT5ReasonCode = .success,
        sessionPresent: Bool = false,
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var variableHeader = Data()
        variableHeader.append(sessionPresent ? 0x01 : 0x00)
        variableHeader.append(reasonCode.rawValue)
        
        var props: [UInt8: Any] = [:]
        if let p = properties { props = p }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        variableHeader.append(contentsOf: propsLen)
        variableHeader.append(propsBytes)
        
        let remLen = variableHeader.count
        var out = Data()
        out.append(MQTTMessageType.CONNACK.rawValue)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(remLen))
        out.append(variableHeader)
        return out
    }
    
    public static func parseConnackV5(_ data: Data, offset: Int = 0) throws -> (Bool, MQTT5ReasonCode, [UInt8: Any], Int) {
        if offset + 2 > data.count { throw MQTTProtocolError.insufficientData("CONNACK") }
        let sessionPresent = (data[offset] & 0x01) != 0
        let reasonCode = MQTT5ReasonCode(rawValue: data[offset + 1]) ?? .unspecifiedError
        var pos = offset + 2
        
        let (propLen, propLenBytes) = try MQTTProtocol.decodeRemainingLength(data, offset: pos)
        pos += propLenBytes
        let (props, _) = try MQTT5PropertyEncoder.decodeProperties(data.subdata(in: pos..<(pos + propLen)), offset: 0)
        pos += propLen
        
        return (sessionPresent, reasonCode, props, pos)
    }
    
    public static func buildPublishV5(
        topic: String,
        payload: Data,
        packetId: UInt16? = nil,
        qos: UInt8 = 0,
        retain: Bool = false,
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var msgType = MQTTMessageType.PUBLISH.rawValue
        if qos > 0 { msgType |= (qos << 1) }
        if retain { msgType |= 0x01 }
        
        var vh = Data()
        vh.append(try MQTTProtocol.encodeString(topic))
        if qos > 0, let pid = packetId {
            vh.append(UInt8((pid >> 8) & 0xFF))
            vh.append(UInt8(pid & 0xFF))
        }
        
        var props: [UInt8: Any] = [:]
        if let p = properties { props = p }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        vh.append(contentsOf: propsLen)
        vh.append(propsBytes)
        
        let pl = vh + payload
        let remLen = pl.count
        var out = Data()
        out.append(msgType)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(remLen))
        out.append(pl)
        return out
    }
    
    public static func buildSubscribeV5(
        packetId: UInt16,
        topic: String,
        qos: UInt8 = 0,
        subscriptionIdentifier: Int? = nil,
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var vh = Data()
        vh.append(UInt8((packetId >> 8) & 0xFF))
        vh.append(UInt8(packetId & 0xFF))
        
        var props: [UInt8: Any] = [:]
        if let si = subscriptionIdentifier {
            props[MQTT5PropertyType.subscriptionIdentifier.rawValue] = si
        }
        if let p = properties { props.merge(p) { (_, new) in new } }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        vh.append(contentsOf: propsLen)
        vh.append(propsBytes)
        
        var pl = Data()
        pl.append(try MQTTProtocol.encodeString(topic))
        pl.append(qos & 0x03)
        
        let rem = vh.count + pl.count
        var out = Data()
        out.append(MQTTMessageType.SUBSCRIBE.rawValue | 0x02)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(rem))
        out.append(vh)
        out.append(pl)
        return out
    }
    
    public static func buildSubackV5(
        packetId: UInt16,
        reasonCodes: [MQTT5ReasonCode],
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var vh = Data()
        vh.append(UInt8((packetId >> 8) & 0xFF))
        vh.append(UInt8(packetId & 0xFF))
        
        var props: [UInt8: Any] = [:]
        if let p = properties { props = p }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        vh.append(contentsOf: propsLen)
        vh.append(propsBytes)
        
        var pl = Data()
        for rc in reasonCodes {
            pl.append(rc.rawValue)
        }
        
        let rem = vh.count + pl.count
        var out = Data()
        out.append(MQTTMessageType.SUBACK.rawValue)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(rem))
        out.append(vh)
        out.append(pl)
        return out
    }
    
    public static func parseSubackV5(_ data: Data, offset: Int = 0) throws -> (UInt16, [MQTT5ReasonCode], [UInt8: Any], Int) {
        if offset + 2 > data.count { throw MQTTProtocolError.insufficientData("SUBACK packet ID") }
        let pid = (UInt16(data[offset] & 0xFF) << 8) | UInt16(data[offset + 1] & 0xFF)
        var pos = offset + 2
        
        let (propLen, propLenBytes) = try MQTTProtocol.decodeRemainingLength(data, offset: pos)
        pos += propLenBytes
        let (props, _) = try MQTT5PropertyEncoder.decodeProperties(data.subdata(in: pos..<(pos + propLen)), offset: 0)
        pos += propLen
        
        var reasonCodes: [MQTT5ReasonCode] = []
        while pos < data.count {
            reasonCodes.append(MQTT5ReasonCode(rawValue: data[pos]))
            pos += 1
        }
        
        return (pid, reasonCodes, props, pos)
    }
    
    public static func buildUnsubscribeV5(
        packetId: UInt16,
        topics: [String],
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var vh = Data()
        vh.append(UInt8((packetId >> 8) & 0xFF))
        vh.append(UInt8(packetId & 0xFF))
        
        var props: [UInt8: Any] = [:]
        if let p = properties { props = p }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        vh.append(contentsOf: propsLen)
        vh.append(propsBytes)
        
        var pl = Data()
        for t in topics {
            pl.append(try MQTTProtocol.encodeString(t))
        }
        
        let rem = vh.count + pl.count
        var out = Data()
        out.append(MQTTMessageType.UNSUBSCRIBE.rawValue | 0x02)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(rem))
        out.append(vh)
        out.append(pl)
        return out
    }
    
    public static func buildUnsubackV5(
        packetId: UInt16,
        reasonCodes: [MQTT5ReasonCode]? = nil,
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var vh = Data()
        vh.append(UInt8((packetId >> 8) & 0xFF))
        vh.append(UInt8(packetId & 0xFF))
        
        var props: [UInt8: Any] = [:]
        if let p = properties { props = p }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        vh.append(contentsOf: propsLen)
        vh.append(propsBytes)
        
        var pl = Data()
        if let rcs = reasonCodes {
            for rc in rcs {
                pl.append(rc.rawValue)
            }
        }
        
        let rem = vh.count + pl.count
        var out = Data()
        out.append(MQTTMessageType.UNSUBACK.rawValue)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(rem))
        out.append(vh)
        out.append(pl)
        return out
    }
    
    public static func buildDisconnectV5(
        reasonCode: MQTT5ReasonCode = .normalDisconnectionDisc,
        properties: [UInt8: Any]? = nil
    ) throws -> Data {
        var vh = Data()
        vh.append(reasonCode.rawValue)
        
        var props: [UInt8: Any] = [:]
        if let p = properties { props = p }
        let propsBytes = try MQTT5PropertyEncoder.encodeProperties(props)
        let propsLen = try MQTTProtocol.encodeRemainingLength(propsBytes.count)
        vh.append(contentsOf: propsLen)
        vh.append(propsBytes)
        
        let remLen = vh.count
        var out = Data()
        out.append(MQTTMessageType.DISCONNECT.rawValue)
        out.append(contentsOf: try MQTTProtocol.encodeRemainingLength(remLen))
        out.append(vh)
        return out
    }
}
