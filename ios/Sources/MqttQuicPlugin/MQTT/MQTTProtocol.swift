//
// MQTTProtocol.swift
// MqttQuicPlugin
//
// MQTT 3.1.1 encode/decode. Matches MQTTD mqttd/protocol.py.
//

import Foundation

public enum MQTTProtocolError: Error {
    case insufficientData(String)
    case invalidRemainingLength(Int)
    case invalidUTF8
}

public final class MQTTProtocol {

    public static let protocolName = "MQTT"

    // MARK: - Remaining length

    /// Encode remaining length (variable-length, 1–4 bytes). Max 268_435_455.
    public static func encodeRemainingLength(_ length: Int) throws -> [UInt8] {
        if length < 0 || length > 268_435_455 {
            throw MQTTProtocolError.invalidRemainingLength(length)
        }
        var enc: [UInt8] = []
        var n = length
        repeat {
            var b = UInt8(n % 128)
            n /= 128
            if n > 0 { b |= 0x80 }
            enc.append(b)
        } while n > 0
        return enc
    }

    /// Decode remaining length. Returns (length, bytesConsumed).
    public static func decodeRemainingLength(_ data: Data, offset: Int = 0) throws -> (Int, Int) {
        var mul: Int = 1
        var len: Int = 0
        var i = offset
        for _ in 0..<4 {
            if i >= data.count { throw MQTTProtocolError.insufficientData("remaining length") }
            let b = data[i]
            len += Int(b & 0x7F) * mul
            i += 1
            if (b & 0x80) == 0 { break }
            mul *= 128
        }
        return (len, i - offset)
    }

    // MARK: - String (2-byte length + UTF-8)

    public static func encodeString(_ s: String) throws -> Data {
        guard let utf8 = s.data(using: .utf8) else { throw MQTTProtocolError.invalidUTF8 }
        let count = utf8.count
        if count > 0xFFFF { throw MQTTProtocolError.insufficientData("string too long") }
        var out = Data(capacity: 2 + count)
        out.append(UInt8((count >> 8) & 0xFF))
        out.append(UInt8(count & 0xFF))
        out.append(utf8)
        return out
    }

    /// Returns (string, newOffset).
    public static func decodeString(_ data: Data, offset: Int) throws -> (String, Int) {
        if offset + 2 > data.count { throw MQTTProtocolError.insufficientData("string length") }
        let hi = Int(data[offset] & 0xFF)
        let lo = Int(data[offset + 1] & 0xFF)
        let strLen = (hi << 8) | lo
        let start = offset + 2
        if start + strLen > data.count { throw MQTTProtocolError.insufficientData("string content") }
        let sub = data.subdata(in: start..<(start + strLen))
        guard let s = String(data: sub, encoding: .utf8) else { throw MQTTProtocolError.invalidUTF8 }
        return (s, start + strLen)
    }

    // MARK: - Fixed header

    /// (messageType, remainingLength, bytesConsumed)
    public static func parseFixedHeader(_ data: Data) throws -> (UInt8, Int, Int) {
        if data.count < 2 { throw MQTTProtocolError.insufficientData("fixed header") }
        let msgType = data[0]
        let (rem, consumed) = try decodeRemainingLength(data, offset: 1)
        return (msgType, rem, 1 + consumed)
    }

    // MARK: - CONNECT (client → server)

    public static func buildConnect(
        clientId: String,
        username: String? = nil,
        password: String? = nil,
        keepalive: UInt16 = 20,
        cleanSession: Bool = true
    ) throws -> Data {
        var variableHeader = Data()
        variableHeader.append(try encodeString(Self.protocolName))
        variableHeader.append(MQTTProtocolLevel.v311)
        var flags: UInt8 = 0
        if cleanSession { flags |= MQTTConnectFlags.cleanSession }
        if username != nil { flags |= MQTTConnectFlags.username }
        if password != nil { flags |= MQTTConnectFlags.password }
        variableHeader.append(flags)
        variableHeader.append(UInt8((keepalive >> 8) & 0xFF))
        variableHeader.append(UInt8(keepalive & 0xFF))

        var payload = Data()
        payload.append(try encodeString(clientId))
        if let u = username { payload.append(try encodeString(u)) }
        if let p = password { payload.append(try encodeString(p)) }

        let remLen = variableHeader.count + payload.count
        var fixed = Data()
        fixed.append(MQTTMessageType.CONNECT.rawValue)
        fixed.append(contentsOf: try encodeRemainingLength(remLen))

        var out = Data()
        out.append(fixed)
        out.append(variableHeader)
        out.append(payload)
        return out
    }

    // MARK: - CONNACK (server → client)

    public static func buildConnack(returnCode: UInt8 = MQTTConnAckCode.accepted.rawValue) -> Data {
        var out = Data()
        out.append(MQTTMessageType.CONNACK.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(2))
        out.append(0x00) // flags
        out.append(returnCode)
        return out
    }

    /// Parse CONNACK variable header. Assumes fixed header already consumed.
    /// Returns (sessionPresent, returnCode).
    public static func parseConnack(_ data: Data, offset: Int = 0) throws -> (Bool, UInt8) {
        if offset + 2 > data.count { throw MQTTProtocolError.insufficientData("CONNACK") }
        let flags = data[offset]
        let rc = data[offset + 1]
        return ((flags & 0x01) != 0, rc)
    }

    // MARK: - PUBLISH

    public static func buildPublish(
        topic: String,
        payload: Data,
        packetId: UInt16? = nil,
        qos: UInt8 = 0,
        retain: Bool = false
    ) throws -> Data {
        var msgType = MQTTMessageType.PUBLISH.rawValue
        if qos > 0 { msgType |= (qos << 1) }
        if retain { msgType |= 0x01 }

        var vh = Data()
        vh.append(try encodeString(topic))
        if qos > 0, let pid = packetId {
            vh.append(UInt8((pid >> 8) & 0xFF))
            vh.append(UInt8(pid & 0xFF))
        }
        var pl = vh
        pl.append(payload)
        let remLen = pl.count
        var out = Data()
        out.append(msgType)
        out.append(contentsOf: try encodeRemainingLength(remLen))
        out.append(pl)
        return out
    }

    /// Parse PUBLISH payload (after fixed header). Assumes fixed header already parsed for QoS.
    /// Returns (topic, packetId?, payload, newOffset). packetId only for QoS > 0.
    public static func parsePublish(_ data: Data, offset: Int, qos: UInt8) throws -> (String, UInt16?, Data, Int) {
        var off = offset
        let (topic, next) = try decodeString(data, offset: off)
        off = next
        var pid: UInt16? = nil
        if qos > 0 {
            if off + 2 > data.count { throw MQTTProtocolError.insufficientData("PUBLISH packet ID") }
            pid = (UInt16(data[off]) << 8) | UInt16(data[off + 1])
            off += 2
        }
        let payload = data.subdata(in: off..<data.count)
        return (topic, pid, payload, data.count)
    }

    // MARK: - PUBACK

    public static func buildPuback(packetId: UInt16) -> Data {
        var out = Data()
        out.append(MQTTMessageType.PUBACK.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(2))
        out.append(UInt8((packetId >> 8) & 0xFF))
        out.append(UInt8(packetId & 0xFF))
        return out
    }

    public static func parsePuback(_ data: Data, offset: Int = 0) throws -> UInt16 {
        if offset + 2 > data.count { throw MQTTProtocolError.insufficientData("PUBACK") }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    // MARK: - SUBSCRIBE

    public static func buildSubscribe(packetId: UInt16, topic: String, qos: UInt8 = 0) throws -> Data {
        var out = Data()
        out.append(MQTTMessageType.SUBSCRIBE.rawValue | 0x02) // QoS 1 required
        var vh = Data()
        vh.append(UInt8((packetId >> 8) & 0xFF))
        vh.append(UInt8(packetId & 0xFF))
        var pl = Data()
        pl.append(try encodeString(topic))
        pl.append(qos & 0x03)
        let rem = vh.count + pl.count
        out.append(contentsOf: try encodeRemainingLength(rem))
        out.append(vh)
        out.append(pl)
        return out
    }

    /// Parse SUBSCRIBE. Returns (packetId, topic, qos, newOffset).
    public static func parseSubscribe(_ data: Data, offset: Int = 0) throws -> (UInt16, String, UInt8, Int) {
        var off = offset
        if off + 2 > data.count { throw MQTTProtocolError.insufficientData("SUBSCRIBE packet ID") }
        let pid = (UInt16(data[off]) << 8) | UInt16(data[off + 1])
        off += 2
        let (topic, next) = try decodeString(data, offset: off)
        off = next
        if off >= data.count { throw MQTTProtocolError.insufficientData("SUBSCRIBE QoS") }
        let qos = data[off] & 0x03
        off += 1
        return (pid, topic, qos, off)
    }

    // MARK: - SUBACK

    public static func buildSuback(packetId: UInt16, returnCode: UInt8 = 0) -> Data {
        var out = Data()
        out.append(MQTTMessageType.SUBACK.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(3))
        out.append(UInt8((packetId >> 8) & 0xFF))
        out.append(UInt8(packetId & 0xFF))
        out.append(returnCode)
        return out
    }

    /// Parse SUBACK. Returns (packetId, returnCode, newOffset).
    public static func parseSuback(_ data: Data, offset: Int = 0) throws -> (UInt16, UInt8, Int) {
        if offset + 3 > data.count { throw MQTTProtocolError.insufficientData("SUBACK") }
        let pid = (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        let rc = data[offset + 2]
        return (pid, rc, offset + 3)
    }

    // MARK: - UNSUBSCRIBE / UNSUBACK

    public static func buildUnsubscribe(packetId: UInt16, topics: [String]) throws -> Data {
        var vh = Data()
        vh.append(UInt8((packetId >> 8) & 0xFF))
        vh.append(UInt8(packetId & 0xFF))
        var pl = Data()
        for t in topics { pl.append(try encodeString(t)) }
        let rem = vh.count + pl.count
        var out = Data()
        out.append(MQTTMessageType.UNSUBSCRIBE.rawValue | 0x02)
        out.append(contentsOf: try encodeRemainingLength(rem))
        out.append(vh)
        out.append(pl)
        return out
    }

    public static func buildUnsuback(packetId: UInt16) -> Data {
        var out = Data()
        out.append(MQTTMessageType.UNSUBACK.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(2))
        out.append(UInt8((packetId >> 8) & 0xFF))
        out.append(UInt8(packetId & 0xFF))
        return out
    }

    public static func parseUnsubscribe(_ data: Data, offset: Int = 0) throws -> (UInt16, [String], Int) {
        var off = offset
        if off + 2 > data.count { throw MQTTProtocolError.insufficientData("UNSUBSCRIBE packet ID") }
        let pid = (UInt16(data[off]) << 8) | UInt16(data[off + 1])
        off += 2
        var topics: [String] = []
        while off < data.count {
            let (t, next) = try decodeString(data, offset: off)
            topics.append(t)
            off = next
        }
        return (pid, topics, off)
    }

    // MARK: - PINGREQ / PINGRESP / DISCONNECT

    public static func buildPingreq() -> Data {
        var out = Data()
        out.append(MQTTMessageType.PINGREQ.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(0))
        return out
    }

    public static func buildPingresp() -> Data {
        var out = Data()
        out.append(MQTTMessageType.PINGRESP.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(0))
        return out
    }

    public static func buildDisconnect() -> Data {
        var out = Data()
        out.append(MQTTMessageType.DISCONNECT.rawValue)
        out.append(contentsOf: try! encodeRemainingLength(0))
        return out
    }
}
