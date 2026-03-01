import Foundation
import Network
import Observation

@MainActor
@Observable
final class DeviceDiscoveryService {
    private let serviceType = UDPAudioTransport.serviceType
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.samroman.quadio.discovery")

    var discoveredClients: [ClientDevice] = []
    var assignments: [ChannelID: ClientDevice.ID] = [:]

    func start(for role: AppRole) {
        switch role {
        case .host:
            startBrowsing()
        case .client:
            break
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        discoveredClients.removeAll()
        assignments.removeAll()
    }

    func assignNextAvailableChannel(to client: ClientDevice) {
        guard let next = ChannelID.allCases.first(where: { assignments[$0] == nil }) else {
            return
        }
        assignments[next] = client.id
    }

    func setAssignment(for channel: ChannelID, clientID: ClientDevice.ID?) {
        assignments[channel] = clientID
    }

    func assignmentLabel(for channel: ChannelID) -> String {
        guard let clientID = assignments[channel],
              let client = discoveredClients.first(where: { $0.id == clientID }) else {
            return "Unassigned"
        }
        return client.name
    }

    func assignedChannels(for client: ClientDevice) -> [ChannelID] {
        assignments.compactMap { channel, clientID in
            clientID == client.id ? channel : nil
        }
        .sorted { $0.rawValue < $1.rawValue }
    }

    private func startBrowsing() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser.stateUpdateHandler = { _ in }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            Task { @MainActor in
                self.discoveredClients = results.map { result in
                    let endpoint = result.endpoint
                    return ClientDevice(name: endpoint.debugName, endpoint: endpoint)
                }
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }
}

private extension NWEndpoint {
    var debugName: String {
        switch self {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        case .service(let name, _, _, _):
            return name
        default:
            return "Unknown Device"
        }
    }
}
