import XCTest
@testable import Quadio

final class JitterBufferTests: XCTestCase {
    func testJitterBufferReturnsEntriesInPlayOrder() async {
        let buffer = JitterBuffer(targetLeadTimeNanos: 100)

        await buffer.enqueue(.init(sequence: 2,
                                   packet: makePacket(sequence: 2, playAt: 300),
                                   playAtHostTimeNanos: 300))
        await buffer.enqueue(.init(sequence: 1,
                                   packet: makePacket(sequence: 1, playAt: 200),
                                   playAtHostTimeNanos: 200))

        let first = await buffer.nextPlayableEntry(nowHostTimeNanos: 150)
        let second = await buffer.nextPlayableEntry(nowHostTimeNanos: 250)
        let remainingCount = await buffer.bufferedCount()

        XCTAssertEqual(first?.sequence, 1)
        XCTAssertEqual(second?.sequence, 2)
        XCTAssertEqual(remainingCount, 0)
    }

    func testJitterBufferDropsDuplicateAndOldSequences() async {
        let buffer = JitterBuffer(targetLeadTimeNanos: 100)

        await buffer.enqueue(.init(sequence: 5,
                                   packet: makePacket(sequence: 5, playAt: 100),
                                   playAtHostTimeNanos: 100))
        _ = await buffer.nextPlayableEntry(nowHostTimeNanos: 50)

        await buffer.enqueue(.init(sequence: 5,
                                   packet: makePacket(sequence: 5, playAt: 120),
                                   playAtHostTimeNanos: 120))
        await buffer.enqueue(.init(sequence: 4,
                                   packet: makePacket(sequence: 4, playAt: 80),
                                   playAtHostTimeNanos: 80))
        let remainingCount = await buffer.bufferedCount()

        XCTAssertEqual(remainingCount, 0)
    }

    private func makePacket(sequence: UInt32, playAt: UInt64) -> TransportPacket {
        let header = TransportPacketHeader(channelID: .frontLeft,
                                           streamID: 1,
                                           sequence: sequence,
                                           hostTimeNanos: playAt,
                                           playAtHostTimeNanos: playAt,
                                           sampleRate: 44_100,
                                           frameCount: 1,
                                           payloadFormat: .muLaw8)
        return TransportPacket(header: header, payload: Data([0xFF]))
    }
}
