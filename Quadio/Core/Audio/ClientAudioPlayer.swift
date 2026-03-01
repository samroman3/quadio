import AVFoundation
import Darwin
import Foundation

@MainActor
final class ClientAudioPlayer {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let jitterBuffer = JitterBuffer()

    private var configuredSampleRate: Double?
    private var sessionConfigured = false
    private var lastScheduledHostTime: UInt64 = 0
    private let minimumLeadTimeNanos: UInt64 = 120_000_000
    private var drainTask: Task<Void, Never>?
    private var hostTimeOffsetNanos: Int64 = 0

    init() {
        engine.attach(playerNode)
    }

    deinit {
        drainTask?.cancel()
    }

    func enqueue(_ packet: TransportPacket, hostNowNanos: UInt64) {
        guard packet.header.packetType == .audioPCM16 else {
            return
        }

        updateHostTimeOffset(using: hostNowNanos)

        Task {
            await jitterBuffer.enqueue(.init(sequence: packet.header.sequence,
                                             packet: packet,
                                             playAtHostTimeNanos: packet.header.playAtHostTimeNanos))
        }

        ensureDrainLoop(initialHostNowNanos: hostNowNanos)
    }

    func reset() {
        drainTask?.cancel()
        drainTask = nil
        playerNode.stop()
        lastScheduledHostTime = 0
        Task {
            await jitterBuffer.reset()
        }
    }

    private func ensureDrainLoop(initialHostNowNanos: UInt64) {
        guard drainTask == nil else { return }

        drainTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var hostNowNanos = max(initialHostNowNanos, self.projectedHostNowNanos())

            while !Task.isCancelled {
                while let entry = await self.jitterBuffer.nextPlayableEntry(nowHostTimeNanos: hostNowNanos) {
                    self.schedule(entry.packet, hostNowNanos: hostNowNanos)
                    hostNowNanos = max(hostNowNanos, entry.playAtHostTimeNanos)
                }

                hostNowNanos = self.projectedHostNowNanos()

                do {
                    try await Task.sleep(nanoseconds: 10_000_000)
                } catch {
                    break
                }
            }

            self.drainTask = nil
        }
    }

    private func schedule(_ packet: TransportPacket, hostNowNanos: UInt64) {
        guard let samples = decodeSamples(from: packet),
              !samples.isEmpty else {
            return
        }

        let packetSampleRate = Double(packet.header.sampleRate)
        reconfigureIfNeeded(sampleRate: packetSampleRate)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: packetSampleRate,
                                         channels: 1,
                                         interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)

        for index in samples.indices {
            channel[index] = samples[index]
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }

        let playAt = max(packet.header.playAtHostTimeNanos, hostNowNanos + minimumLeadTimeNanos)
        let scheduleAt = hostTimeTicks(forHostTimeNanos: max(playAt, lastScheduledHostTime + 1))
        lastScheduledHostTime = playAt
        playerNode.scheduleBuffer(buffer, at: AVAudioTime(hostTime: scheduleAt))
    }

    private func reconfigureIfNeeded(sampleRate: Double) {
        if configuredSampleRate == sampleRate {
            if !engine.isRunning {
                try? engine.start()
            }
            return
        }

        if !sessionConfigured {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default)
            try? session.setActive(true)
            sessionConfigured = true
        }

        if engine.isRunning {
            engine.stop()
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: sampleRate,
                                   channels: 1,
                                   interleaved: false)

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try? engine.start()
        configuredSampleRate = sampleRate
        lastScheduledHostTime = 0
    }

    private func decodeSamples(from packet: TransportPacket) -> [Float]? {
        switch packet.header.payloadFormat {
        case .pcm16:
            return packet.payload.int16MonoSamples?.map { Float($0) / Float(Int16.max) }
        case .muLaw8:
            return packet.payload.muLawMonoSamples
        }
    }

    private func hostTimeTicks(forHostTimeNanos nanos: UInt64) -> UInt64 {
        let nowTicks = mach_absolute_time()
        let localNowNanos = DispatchTime.now().uptimeNanoseconds
        let localTargetNanos: UInt64
        if hostTimeOffsetNanos >= 0 {
            localTargetNanos = nanos > UInt64(hostTimeOffsetNanos) ? nanos - UInt64(hostTimeOffsetNanos) : localNowNanos
        } else {
            localTargetNanos = nanos + UInt64(abs(hostTimeOffsetNanos))
        }
        let deltaNanos = localTargetNanos > localNowNanos ? localTargetNanos - localNowNanos : minimumLeadTimeNanos
        let deltaSeconds = Double(deltaNanos) / 1_000_000_000
        return nowTicks + AVAudioTime.hostTime(forSeconds: deltaSeconds)
    }

    private func updateHostTimeOffset(using hostNowNanos: UInt64) {
        let localNow = DispatchTime.now().uptimeNanoseconds
        let observedOffset = Int64(hostNowNanos) - Int64(localNow)
        hostTimeOffsetNanos = ((hostTimeOffsetNanos * 3) + observedOffset) / 4
    }

    private func projectedHostNowNanos() -> UInt64 {
        let localNow = DispatchTime.now().uptimeNanoseconds
        if hostTimeOffsetNanos >= 0 {
            return localNow + UInt64(hostTimeOffsetNanos)
        }
        return localNow &- UInt64(abs(hostTimeOffsetNanos))
    }
}
