import AVFoundation
import Foundation

enum AudioFileDecoder {
    static func decodeFile(at url: URL) throws -> DecodedAsset {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat

        guard sourceFormat.channelCount == 2 else {
            throw AudioPipelineError.unsupportedChannelCount(Int(sourceFormat.channelCount))
        }

        let sourceBuffer = try readEntireFile(file)
        let workingBuffer = try convertIfNeeded(sourceBuffer)
        let decoder = QSDecodeEngine()

        guard let decoded = decoder.decode(buffer: workingBuffer) else {
            throw AudioPipelineError.decodeFailed
        }

        return DecodedAsset(sourceName: url.lastPathComponent,
                            sampleRate: decoded.sampleRate,
                            frameCount: Int(decoded.frameCount),
                            channels: [
                                .frontLeft: decoded.frontLeft,
                                .frontRight: decoded.frontRight,
                                .rearLeft: decoded.rearLeft,
                                .rearRight: decoded.rearRight,
                            ])
    }

    private static func readEntireFile(_ file: AVAudioFile) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioPipelineError.bufferAllocationFailed
        }

        try file.read(into: buffer)
        return buffer
    }

    private static func convertIfNeeded(_ sourceBuffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard sourceBuffer.format.channelCount == 2 else {
            throw AudioPipelineError.unsupportedChannelCount(Int(sourceBuffer.format.channelCount))
        }

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: sourceBuffer.format.sampleRate,
                                               channels: 2,
                                               interleaved: false) else {
            throw AudioPipelineError.bufferAllocationFailed
        }

        if sourceBuffer.format.commonFormat == .pcmFormatFloat32,
           sourceBuffer.format.sampleRate == targetFormat.sampleRate,
           sourceBuffer.format.channelCount == targetFormat.channelCount,
           sourceBuffer.floatChannelData != nil {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceBuffer.format, to: targetFormat),
              let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: sourceBuffer.frameCapacity) else {
            throw AudioPipelineError.conversionFailed
        }

        var didProvideInput = false
        var conversionError: NSError?

        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw conversionError
        }

        guard status != .error else {
            throw AudioPipelineError.conversionFailed
        }

        return outputBuffer
    }
}
