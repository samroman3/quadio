import Foundation

struct DecodedAsset {
    let sourceName: String
    let sampleRate: Double
    let frameCount: Int
    let channels: [ChannelID: [Float]]

    subscript(channel: ChannelID) -> [Float] {
        channels[channel] ?? []
    }
}
