import Foundation
import Network
import Observation

@MainActor
@Observable
final class UDPAudioTransport {
    static let defaultPort: UInt16 = 40000
    static let serviceType = "_quadio._udp"

    private let queue = DispatchQueue(label: "com.samroman.quadio.transport")
    private var listener: NWListener?
    private var outgoingConnections: [ClientDevice.ID: NWConnection] = [:]

    private(set) var healthSummary = "No packets sent yet"
    var onPacket: ((TransportPacket) -> Void)?

    func startClientListener(port: UInt16 = 40000, serviceName: String = ProcessInfo.processInfo.hostName) {
        guard listener == nil else { return }

        do {
            let listener = try NWListener(using: .udp, on: NWEndpoint.Port(rawValue: port) ?? .any)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)
            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                Task { @MainActor in
                    self.receive(on: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    self?.healthSummary = "Client listener: \(String(describing: state))"
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            healthSummary = "Transport error: \(error.localizedDescription)"
        }
    }

    func send(_ packet: TransportPacket, to client: ClientDevice) {
        guard let endpoint = client.endpoint else { return }

        let connection: NWConnection
        if let existing = outgoingConnections[client.id] {
            connection = existing
        } else {
            let newConnection = NWConnection(to: endpoint, using: .udp)
            newConnection.start(queue: queue)
            outgoingConnections[client.id] = newConnection
            connection = newConnection
        }

        connection.send(content: packet.encoded(), completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.healthSummary = "Send failed: \(error.localizedDescription)"
                } else {
                    self?.healthSummary = "Last packet: \(packet.header.frameCount) frames to \(client.name)"
                }
            }
        })
    }

    func stop() {
        listener?.cancel()
        listener = nil
        outgoingConnections.values.forEach { $0.cancel() }
        outgoingConnections.removeAll()
        healthSummary = "Transport stopped"
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            Task { @MainActor in
                if let data {
                    if let packet = TransportPacket.decode(from: data) {
                        self?.healthSummary = "Received \(packet.header.frameCount) frames"
                        self?.onPacket?(packet)
                    } else {
                        self?.healthSummary = "Received \(data.count) bytes"
                    }
                } else if let error {
                    self?.healthSummary = "Receive failed: \(error.localizedDescription)"
                }
            }

            if error == nil {
                Task { @MainActor in
                    self?.receive(on: connection)
                }
            }
        }
    }
}
