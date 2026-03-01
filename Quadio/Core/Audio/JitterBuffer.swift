import Foundation

actor JitterBuffer {
    struct Entry {
        let sequence: UInt32
        let packet: TransportPacket
        let playAtHostTimeNanos: UInt64
    }

    private var entries: [Entry] = []
    private let targetLeadTimeNanos: UInt64
    private var lastSequence: UInt32?

    init(targetLeadTimeNanos: UInt64 = 250_000_000) {
        self.targetLeadTimeNanos = targetLeadTimeNanos
    }

    func enqueue(_ entry: Entry) {
        if let lastSequence, entry.sequence <= lastSequence {
            return
        }

        if entries.contains(where: { $0.sequence == entry.sequence }) {
            return
        }

        entries.append(entry)
        entries.sort { $0.playAtHostTimeNanos < $1.playAtHostTimeNanos }
    }

    func nextPlayableEntry(nowHostTimeNanos: UInt64) -> Entry? {
        guard let first = entries.first else {
            return nil
        }

        guard first.playAtHostTimeNanos <= nowHostTimeNanos + targetLeadTimeNanos else {
            return nil
        }

        entries.removeFirst()
        lastSequence = first.sequence
        return first
    }

    func bufferedCount() -> Int {
        entries.count
    }

    func reset() {
        entries.removeAll(keepingCapacity: true)
        lastSequence = nil
    }
}
