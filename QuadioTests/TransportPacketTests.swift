import XCTest
@testable import Quadio

final class TransportPacketTests: XCTestCase {
    func testPacketRoundTripPreservesHeaderAndPayload() {
        let header = TransportPacketHeader(channelID: .rearLeft,
                                           streamID: 42,
                                           sequence: 7,
                                           hostTimeNanos: 123_456,
                                           playAtHostTimeNanos: 789_012,
                                           sampleRate: 44_100,
                                           frameCount: 4,
                                           payloadFormat: .pcm16)
        let payload = Data([0x34, 0x12, 0x78, 0x56])
        let packet = TransportPacket(header: header, payload: payload)

        let decoded = TransportPacket.decode(from: packet.encoded())

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.header.channelID, .rearLeft)
        XCTAssertEqual(decoded?.header.streamID, 42)
        XCTAssertEqual(decoded?.header.sequence, 7)
        XCTAssertEqual(decoded?.header.hostTimeNanos, 123_456)
        XCTAssertEqual(decoded?.header.playAtHostTimeNanos, 789_012)
        XCTAssertEqual(decoded?.header.sampleRate, 44_100)
        XCTAssertEqual(decoded?.header.frameCount, 4)
        XCTAssertEqual(decoded?.header.payloadFormat, .pcm16)
        XCTAssertEqual(decoded?.payload, payload)
    }

    func testPCM16DataRoundTripsToSamples() {
        let source: [Float] = [-1.0, -0.25, 0.0, 0.25, 1.0]

        let data = source.pcm16Data(start: 0, count: source.count)
        let decoded = data.int16MonoSamples

        XCTAssertEqual(decoded?.count, source.count)
        XCTAssertEqual(decoded?.first, -Int16.max)
        XCTAssertEqual(decoded?[2], 0)
        XCTAssertEqual(decoded?.last, Int16.max)
    }

    func testMuLawEncodingStaysWithinReasonableTolerance() {
        let source: [Float] = [-0.8, -0.3, 0.0, 0.3, 0.8]

        let encoded = source.muLawData(start: 0, count: source.count)
        let decoded = encoded.muLawMonoSamples

        XCTAssertEqual(decoded?.count, source.count)

        zip(source, decoded ?? []).forEach { original, recovered in
            XCTAssertLessThan(abs(original - recovered), 0.12)
        }
    }
}
