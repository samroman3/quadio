import Foundation

enum TransportPacketType: UInt8 {
    case audioPCM16 = 1
}

enum PayloadFormat: UInt8, CaseIterable, Identifiable {
    case pcm16 = 1
    case muLaw8 = 2

    var id: UInt8 { rawValue }

    var displayName: String {
        switch self {
        case .pcm16:
            return "PCM 16-bit"
        case .muLaw8:
            return "mu-Law 8-bit"
        }
    }
}

struct TransportPacketHeader {
    static let magic: UInt32 = 0x5144554F
    static let byteCount = 40

    var version: UInt8 = 1
    var packetType: TransportPacketType = .audioPCM16
    var channelID: ChannelID
    var flags: UInt8 = 0
    var streamID: UInt32
    var sequence: UInt32
    var hostTimeNanos: UInt64
    var playAtHostTimeNanos: UInt64
    var sampleRate: UInt32
    var frameCount: UInt16
    var payloadFormat: PayloadFormat = .muLaw8
    var reserved: UInt8 = 0

    func encoded() -> Data {
        var data = Data(capacity: Self.byteCount)
        data.append(bigEndian: Self.magic)
        data.append(version)
        data.append(packetType.rawValue)
        data.append(channelID.rawValue)
        data.append(flags)
        data.append(bigEndian: streamID)
        data.append(bigEndian: sequence)
        data.append(bigEndian: hostTimeNanos)
        data.append(bigEndian: playAtHostTimeNanos)
        data.append(bigEndian: sampleRate)
        data.append(bigEndian: frameCount)
        data.append(payloadFormat.rawValue)
        data.append(reserved)
        return data
    }

    static func decode(from data: Data) -> TransportPacketHeader? {
        guard data.count >= byteCount,
              let magic = data.readUInt32(at: 0),
              magic == Self.magic,
              let packetType = TransportPacketType(rawValue: data[5]),
              let channelID = ChannelID(rawValue: data[6]),
              let streamID = data.readUInt32(at: 8),
              let sequence = data.readUInt32(at: 12),
              let hostTime = data.readUInt64(at: 16),
              let playAt = data.readUInt64(at: 24),
              let sampleRate = data.readUInt32(at: 32),
              let frameCount = data.readUInt16(at: 36),
              let payloadFormat = PayloadFormat(rawValue: data[38]) else {
            return nil
        }

        return TransportPacketHeader(version: data[4],
                                     packetType: packetType,
                                     channelID: channelID,
                                     flags: data[7],
                                     streamID: streamID,
                                     sequence: sequence,
                                     hostTimeNanos: hostTime,
                                     playAtHostTimeNanos: playAt,
                                     sampleRate: sampleRate,
                                     frameCount: frameCount,
                                     payloadFormat: payloadFormat,
                                     reserved: data[39])
    }
}

struct TransportPacket {
    var header: TransportPacketHeader
    var payload: Data

    func encoded() -> Data {
        var data = header.encoded()
        data.append(payload)
        return data
    }

    static func decode(from data: Data) -> TransportPacket? {
        guard let header = TransportPacketHeader.decode(from: data) else {
            return nil
        }

        return TransportPacket(header: header, payload: Data(data.dropFirst(TransportPacketHeader.byteCount)))
    }
}

extension Data {
    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }

    func readUInt16(at offset: Int) -> UInt16? {
        guard offset + 2 <= count else { return nil }
        return (UInt16(self[offset]) << 8) | UInt16(self[offset + 1])
    }

    func readUInt32(at offset: Int) -> UInt32? {
        guard offset + 4 <= count else { return nil }
        var value: UInt32 = 0
        for byteOffset in 0..<4 {
            value = (value << 8) | UInt32(self[offset + byteOffset])
        }
        return value
    }

    func readUInt64(at offset: Int) -> UInt64? {
        guard offset + 8 <= count else { return nil }
        var value: UInt64 = 0
        for byteOffset in 0..<8 {
            value = (value << 8) | UInt64(self[offset + byteOffset])
        }
        return value
    }
}

extension Data {
    var int16MonoSamples: [Int16]? {
        guard count.isMultiple(of: MemoryLayout<Int16>.size) else {
            return nil
        }

        let sampleCount = count / MemoryLayout<Int16>.size
        return withUnsafeBytes { rawBuffer in
            let buffer = rawBuffer.bindMemory(to: Int16.self)
            return Array(buffer.prefix(sampleCount)).map(Int16.init(littleEndian:))
        }
    }

    var muLawMonoSamples: [Float]? {
        map { MuLawCodec.decode($0) }
    }
}

extension Array where Element == Float {
    func pcm16Data(start: Int, count frameCount: Int) -> Data {
        guard start < endIndex, frameCount > 0 else {
            return Data()
        }

        let end = Swift.min(start + frameCount, endIndex)
        var data = Data(capacity: (end - start) * MemoryLayout<Int16>.size)
        for index in start..<end {
            let clamped = Swift.max(-1.0, Swift.min(1.0, self[index]))
            let sample = Int16((clamped * Float(Int16.max)).rounded())
            data.append(littleEndian: sample)
        }
        return data
    }

    func muLawData(start: Int, count frameCount: Int) -> Data {
        guard start < endIndex, frameCount > 0 else {
            return Data()
        }

        let end = Swift.min(start + frameCount, endIndex)
        var data = Data(capacity: end - start)
        for index in start..<end {
            let clamped = Swift.max(-1.0, Swift.min(1.0, self[index]))
            data.append(MuLawCodec.encode(clamped))
        }
        return data
    }
}

extension Data {
    mutating func append<T: FixedWidthInteger>(littleEndian value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }
}

enum MuLawCodec {
    private static let bias = 0x84
    private static let clip = 32635

    static func encode(_ sample: Float) -> UInt8 {
        var pcm = Int((sample * 32767.0).rounded())
        let signMask = pcm < 0 ? 0x80 : 0x00
        if pcm < 0 {
            pcm = -pcm
        }
        pcm = Swift.min(pcm, clip)
        pcm += bias

        var exponent = 7
        var expMask = 0x4000
        while exponent > 0 && (pcm & expMask) == 0 {
            exponent -= 1
            expMask >>= 1
        }

        let mantissa = (pcm >> (exponent + 3)) & 0x0F
        let muLaw = ~(signMask | (exponent << 4) | mantissa)
        return UInt8(truncatingIfNeeded: muLaw)
    }

    static func decode(_ byte: UInt8) -> Float {
        let value = Int(~byte)
        let sign = value & 0x80
        let exponent = (value >> 4) & 0x07
        let mantissa = value & 0x0F

        var pcm = ((mantissa << 3) + bias) << exponent
        pcm -= bias
        if sign != 0 {
            pcm = -pcm
        }

        return Float(pcm) / 32768.0
    }
}
