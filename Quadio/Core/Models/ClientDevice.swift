import Foundation
import Network

struct ClientDevice: Identifiable, Hashable {
    enum Status: String {
        case available
        case connected
        case unavailable
    }

    let id: UUID
    var name: String
    var endpoint: NWEndpoint?
    var status: Status
    var estimatedLatencyMS: Double?

    init(id: UUID = UUID(), name: String, endpoint: NWEndpoint?, status: Status = .available, estimatedLatencyMS: Double? = nil) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.status = status
        self.estimatedLatencyMS = estimatedLatencyMS
    }
}
