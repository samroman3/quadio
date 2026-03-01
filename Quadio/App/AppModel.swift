import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var selectedRole: AppRole = .host
    var hostState = HostState()
    var clientState = ClientState()

    let audioPipeline = AudioPipeline()
    let discoveryService = DeviceDiscoveryService()
    let transport = UDPAudioTransport()
    let clockSync = ClockSyncService()
    let clientPlayer = ClientAudioPlayer()

    private var streamTask: Task<Void, Never>?
    private var packetSequence: UInt32 = 0
    private let streamID: UInt32 = .random(in: UInt32.min ... UInt32.max)
    private var nextPacketPlayAtHostTimeNanos: UInt64?

    init() {
        transport.onPacket = { [weak self] packet in
            self?.handleIncoming(packet: packet)
        }
    }

    func switchRole(to role: AppRole) {
        stop()
        selectedRole = role
        start()
    }

    func start() {
        discoveryService.start(for: selectedRole)
        if selectedRole == .client {
            transport.startClientListener()
            clockSync.startClientSync()
        } else {
            clockSync.startHostClock()
        }
    }

    func stop() {
        stopStreaming()
        discoveryService.stop()
        transport.stop()
        clockSync.stop()
        clientPlayer.reset()
    }

    func setAssignment(for channel: ChannelID, clientID: ClientDevice.ID?) {
        discoveryService.setAssignment(for: channel, clientID: clientID)
    }

    func importAudioFile(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            hostState.lastError = nil
            hostState.decodedAsset = try audioPipeline.decodeFile(at: url)
            hostState.streamProgress = 0
            nextPacketPlayAtHostTimeNanos = nil
        } catch {
            hostState.lastError = error.localizedDescription
        }
    }

    func loadBundledSample() {
        guard let url = Bundle.main.url(forResource: "qs_test_sequence", withExtension: "wav") else {
            hostState.lastError = "Sample file is missing from this build."
            return
        }

        do {
            hostState.lastError = nil
            hostState.decodedAsset = try audioPipeline.decodeFile(at: url)
            hostState.streamProgress = 0
            nextPacketPlayAtHostTimeNanos = nil
        } catch {
            hostState.lastError = error.localizedDescription
        }
    }

    func startStreaming() {
        guard streamTask == nil,
              let asset = hostState.decodedAsset else {
            return
        }

        let assignedTargets = discoveryService.assignments.compactMap { channel, clientID -> (ChannelID, ClientDevice)? in
            guard let client = discoveryService.discoveredClients.first(where: { $0.id == clientID }) else {
                return nil
            }
            return (channel, client)
        }

        guard !assignedTargets.isEmpty else {
            hostState.lastError = "Assign at least one decoded channel to a discovered client."
            return
        }

        hostState.lastError = nil
        hostState.isStreaming = true

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let framesPerPacket = max(256, Int(asset.sampleRate / 50.0))
            var frameIndex = 0
            let initialLeadTimeNanos = UInt64(hostState.targetLatencyMS * 1_000_000)
            if self.nextPacketPlayAtHostTimeNanos == nil {
                self.nextPacketPlayAtHostTimeNanos = self.clockSync.projectedHostTimeNanos() + initialLeadTimeNanos
            }

            while !Task.isCancelled {
                if frameIndex >= asset.frameCount {
                    frameIndex = 0
                }

                let assignedTargets = self.discoveryService.assignments.compactMap { channel, clientID -> (ChannelID, ClientDevice)? in
                    guard let client = self.discoveryService.discoveredClients.first(where: { $0.id == clientID }) else {
                        return nil
                    }
                    return (channel, client)
                }

                guard !assignedTargets.isEmpty else {
                    self.hostState.lastError = "Streaming stopped because no assigned clients are currently available."
                    break
                }

                let packetFrames = min(framesPerPacket, asset.frameCount - frameIndex)
                let chunkDurationNanos = UInt64((Double(packetFrames) / asset.sampleRate) * 1_000_000_000)
                let hostNow = self.clockSync.projectedHostTimeNanos()
                let packetPlayAt = max(self.nextPacketPlayAtHostTimeNanos ?? hostNow, hostNow + initialLeadTimeNanos)

                for (channel, client) in assignedTargets {
                    let payload: Data
                    switch self.hostState.payloadFormat {
                    case .pcm16:
                        payload = asset[channel].pcm16Data(start: frameIndex, count: packetFrames)
                    case .muLaw8:
                        payload = asset[channel].muLawData(start: frameIndex, count: packetFrames)
                    }
                    let header = TransportPacketHeader(channelID: channel,
                                                       streamID: streamID,
                                                       sequence: packetSequence,
                                                       hostTimeNanos: hostNow,
                                                       playAtHostTimeNanos: packetPlayAt,
                                                       sampleRate: UInt32(asset.sampleRate.rounded()),
                                                       frameCount: UInt16(packetFrames),
                                                       payloadFormat: self.hostState.payloadFormat)
                    transport.send(TransportPacket(header: header, payload: payload), to: client)
                    packetSequence &+= 1
                }

                frameIndex += packetFrames
                hostState.streamProgress = Double(frameIndex) / Double(max(asset.frameCount, 1))
                self.nextPacketPlayAtHostTimeNanos = packetPlayAt + chunkDurationNanos

                do {
                    try await Task.sleep(nanoseconds: chunkDurationNanos)
                } catch {
                    break
                }
            }

            self.hostState.isStreaming = false
            self.hostState.streamProgress = 0
            self.nextPacketPlayAtHostTimeNanos = nil
            self.streamTask = nil
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        hostState.isStreaming = false
        hostState.streamProgress = 0
        nextPacketPlayAtHostTimeNanos = nil
    }

    private func handleIncoming(packet: TransportPacket) {
        clockSync.ingestHostTimestamp(packet.header.hostTimeNanos)
        clientState.assignedChannel = packet.header.channelID
        clientPlayer.enqueue(packet, hostNowNanos: clockSync.projectedHostTimeNanos())
    }
}

enum AppRole: String, CaseIterable, Identifiable {
    case host
    case client

    var id: String { rawValue }

    var title: String {
        switch self {
        case .host:
            return "Host"
        case .client:
            return "Client"
        }
    }

    var subtitle: String {
        switch self {
        case .host:
            return "Decode stereo QS input, assign channels, and stream them."
        case .client:
            return "Advertise on the LAN, receive one routed channel, and play it."
        }
    }
}

struct HostState {
    var streamName = "Session"
    var decodedAsset: DecodedAsset?
    var isStreaming = false
    var streamProgress = 0.0
    var payloadFormat: PayloadFormat = .muLaw8
    var targetLatencyMS: Double = 300
    var lastError: String?
}

struct ClientState {
    var assignedChannel: ChannelID?
}
