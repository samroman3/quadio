import Foundation

struct DecodedAsset: Sendable {
    let sourceName: String
    let sampleRate: Double
    let frameCount: Int
    let channels: [ChannelID: [Float]]

    subscript(channel: ChannelID) -> [Float] {
        channels[channel] ?? []
    }
}
