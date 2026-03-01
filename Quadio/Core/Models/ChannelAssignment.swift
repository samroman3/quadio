import Foundation

struct ChannelAssignment: Identifiable, Hashable {
    let id = UUID()
    let channel: ChannelID
    let clientID: ClientDevice.ID
}
