import AVFoundation
import Foundation

struct DecodedAudioBlock {
    let sampleRate: Double
    let frameCount: AVAudioFrameCount
    let frontLeft: [Float]
    let frontRight: [Float]
    let rearLeft: [Float]
    let rearRight: [Float]
}

final class QSDecodeEngine {
    private var sampleRate: Int32 = 48_000
    private var bridge = QSDecoderBridge(sampleRate: 48_000)

    func decode(buffer: AVAudioPCMBuffer) -> DecodedAudioBlock? {
        guard buffer.format.channelCount == 2,
              let channels = buffer.floatChannelData else {
            return nil
        }

        let incomingSampleRate = Int32(buffer.format.sampleRate.rounded())
        if incomingSampleRate != sampleRate {
            sampleRate = incomingSampleRate
            bridge = QSDecoderBridge(sampleRate: sampleRate)
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return nil
        }
        let left = channels[0]
        let right = channels[1]

        var frontLeft = Array(repeating: Float.zero, count: frameCount)
        var frontRight = Array(repeating: Float.zero, count: frameCount)
        var rearLeft = Array(repeating: Float.zero, count: frameCount)
        var rearRight = Array(repeating: Float.zero, count: frameCount)

        frontLeft.withUnsafeMutableBufferPointer { frontLeftBuffer in
            frontRight.withUnsafeMutableBufferPointer { frontRightBuffer in
                rearLeft.withUnsafeMutableBufferPointer { rearLeftBuffer in
                    rearRight.withUnsafeMutableBufferPointer { rearRightBuffer in
                        guard let frontLeftPointer = frontLeftBuffer.baseAddress,
                              let frontRightPointer = frontRightBuffer.baseAddress,
                              let rearLeftPointer = rearLeftBuffer.baseAddress,
                              let rearRightPointer = rearRightBuffer.baseAddress else {
                            return
                        }

                        bridge.decodeLeft(left,
                                          right: right,
                                          frameCount: UInt32(frameCount),
                                          frontLeft: frontLeftPointer,
                                          frontRight: frontRightPointer,
                                          rearLeft: rearLeftPointer,
                                          rearRight: rearRightPointer)
                    }
                }
            }
        }

        return DecodedAudioBlock(sampleRate: buffer.format.sampleRate,
                                 frameCount: AVAudioFrameCount(frameCount),
                                 frontLeft: frontLeft,
                                 frontRight: frontRight,
                                 rearLeft: rearLeft,
                                 rearRight: rearRight)
    }
}
