//
// MQTTProtocolTests.swift
// Unit tests for MQTT encode/decode. Run via Xcode test target or Swift Package.
//

import XCTest
@testable import MqttQuicPlugin

final class MQTTProtocolTests: XCTestCase {

    func testEncodeDecodeRemainingLength() throws {
        for (len, bytes) in [(0, 1), (127, 1), (128, 2), (16383, 2), (16384, 3), (2_097_151, 3), (2_097_152, 4)] {
            let enc = try MQTTProtocol.encodeRemainingLength(len)
            XCTAssertEqual(enc.count, bytes, "length \(len)")
            let (dec, _) = try MQTTProtocol.decodeRemainingLength(Data(enc), offset: 0)
            XCTAssertEqual(dec, len)
        }
    }

    func testEncodeDecodeString() throws {
        let s = "hello/mqtt"
        let enc = try MQTTProtocol.encodeString(s)
        XCTAssertEqual(enc.count, 2 + s.utf8.count)
        let (dec, _) = try MQTTProtocol.decodeString(enc, offset: 0)
        XCTAssertEqual(dec, s)
    }

    func testBuildConnect() throws {
        let data = try MQTTProtocol.buildConnect(clientId: "test-client", username: "u", password: "p", keepalive: 90, cleanSession: true)
        XCTAssertGreaterThanOrEqual(data.count, 10)
        XCTAssertEqual(data[0], MQTTMessageType.CONNECT.rawValue)
    }

    func testBuildConnack() {
        let data = MQTTProtocol.buildConnack(returnCode: MQTTConnAckCode.accepted.rawValue)
        XCTAssertEqual(data.count, 4)
        XCTAssertEqual(data[0], MQTTMessageType.CONNACK.rawValue)
        XCTAssertEqual(data[3], MQTTConnAckCode.accepted.rawValue)
    }

    func testBuildPublish() throws {
        let payload = Data("hello".utf8)
        let data = try MQTTProtocol.buildPublish(topic: "a/b", payload: payload, qos: 0, retain: false)
        XCTAssertEqual(data[0] & 0xF0, MQTTMessageType.PUBLISH.rawValue)
    }

    func testBuildSubscribeAndSuback() throws {
        let sub = try MQTTProtocol.buildSubscribe(packetId: 1, topic: "t/1", qos: 0)
        XCTAssertEqual(sub[0], MQTTMessageType.SUBSCRIBE.rawValue | 0x02)

        let suback = MQTTProtocol.buildSuback(packetId: 1, returnCode: 0)
        XCTAssertEqual(suback[0], MQTTMessageType.SUBACK.rawValue)
        let (pid, rc, _) = try MQTTProtocol.parseSuback(suback, offset: 2) // skip fixed header (2 bytes)
        XCTAssertEqual(pid, 1)
        XCTAssertEqual(rc, 0)
    }

    func testBuildPingreqPingrespDisconnect() {
        let pr = MQTTProtocol.buildPingreq()
        XCTAssertEqual(pr[0], MQTTMessageType.PINGREQ.rawValue)
        let ps = MQTTProtocol.buildPingresp()
        XCTAssertEqual(ps[0], MQTTMessageType.PINGRESP.rawValue)
        let dc = MQTTProtocol.buildDisconnect()
        XCTAssertEqual(dc[0], MQTTMessageType.DISCONNECT.rawValue)
    }

    func testMockStreamReaderWriter() async throws {
        let buf = MockStreamBuffer(initialReadData: Data([1, 2, 3, 4, 5]))
        let reader = MockStreamReader(buffer: buf)
        let writer = MockStreamWriter(buffer: buf)

        let r1 = try await reader.read(maxBytes: 2)
        XCTAssertEqual(r1, Data([1, 2]))
        let r2 = try await reader.readexactly(3)
        XCTAssertEqual(r2, Data([3, 4, 5]))

        try await writer.write(Data([6, 7, 8]))
        try await writer.drain()
        let written = buf.consumeWrite()
        XCTAssertEqual(written, Data([6, 7, 8]))
    }
}
