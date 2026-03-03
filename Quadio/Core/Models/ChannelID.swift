import Foundation

enum ChannelID: UInt8, CaseIterable, Codable, Identifiable, Sendable {
    case frontLeft = 0
    case frontRight = 1
    case rearLeft = 2
    case rearRight = 3

    var id: UInt8 { rawValue }

    var displayName: String {
        switch self {
        case .frontLeft:
            return "Front Left"
        case .frontRight:
            return "Front Right"
        case .rearLeft:
            return "Rear Left"
        case .rearRight:
            return "Rear Right"
        }
    }
}
