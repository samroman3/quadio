import Foundation
import Observation

@MainActor
@Observable
final class ClockSyncService {
    private(set) var stateSummary = "Idle"

    private enum Mode {
        case idle
        case host
        case client
    }

    private var mode: Mode = .idle
    private var hostOffsetEstimateNanos: Int64 = 0

    func startHostClock() {
        mode = .host
        hostOffsetEstimateNanos = 0
        stateSummary = "Host clock active"
    }

    func startClientSync() {
        mode = .client
        hostOffsetEstimateNanos = 0
        stateSummary = "Client sync warm-up"
    }

    func applyClientEstimate(roundTripNanos: UInt64, offsetNanos: Int64) {
        hostOffsetEstimateNanos = offsetNanos
        stateSummary = "RTT \(roundTripNanos / 1_000_000) ms, offset \(offsetNanos / 1_000_000) ms"
    }

    func ingestHostTimestamp(_ hostTimeNanos: UInt64) {
        let localNow = DispatchTime.now().uptimeNanoseconds
        let observedOffset = Int64(hostTimeNanos) - Int64(localNow)
        hostOffsetEstimateNanos = ((hostOffsetEstimateNanos * 7) + observedOffset) / 8
        stateSummary = "Tracking host offset \(hostOffsetEstimateNanos / 1_000_000) ms"
    }

    func projectedHostTimeNanos() -> UInt64 {
        let localNow = DispatchTime.now().uptimeNanoseconds

        guard mode == .client else {
            return localNow
        }

        if hostOffsetEstimateNanos >= 0 {
            return localNow + UInt64(hostOffsetEstimateNanos)
        }
        return localNow &- UInt64(abs(hostOffsetEstimateNanos))
    }

    func stop() {
        mode = .idle
        stateSummary = "Idle"
    }
}
