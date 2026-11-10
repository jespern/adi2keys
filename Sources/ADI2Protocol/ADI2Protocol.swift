// RME ADI-2 series MIDI SysEx protocol, per RME's "MIDITable_ADI-2" v1.2 (30.10.26),
// https://www.rme-audio.de/downloads/adi2remote_midi_protocol.zip
//
// SysEx payloads here exclude the F0/F7 framing: 00 20 0D <device> <command> <data...>.

public enum Model: UInt8, Sendable {
    case dac = 0x71
    case pro = 0x72
    case pro4 = 0x73   // ADI-2/4 Pro SE/EX

    /// Infers the model from a CoreAudio or CoreMIDI device name such as "ADI-2 Pro (56011377)".
    public init?(deviceName name: String) {
        if name.hasPrefix("ADI-2/4") { self = .pro4 }
        else if name.hasPrefix("ADI-2 Pro") { self = .pro }
        else if name.hasPrefix("ADI-2 DAC") { self = .dac }
        else { return nil }
    }
}

/// Output channel addresses (the 4-bit address field of a parameter container).
public enum Output: Int, Sendable, CaseIterable {
    case line = 3
    case phones12 = 6
    case phones34 = 9

    public init?(name: String) {
        switch name.lowercased() {
        case "line", "main": self = .line
        case "phones", "phones12", "ph12": self = .phones12
        case "phones34", "ph34": self = .phones34
        default: return nil
        }
    }
}

public enum OutputParameter: Int, Sendable {
    case volume = 12   // tenths of a dB, -1145...60
    case mute = 15     // 0/1
}

public enum Volume {
    public static let min = -1145
    public static let max = 60
}

enum Command: UInt8 {
    case toRemote = 0x01
    case toDevice = 0x02
    case request = 0x03
    case status = 0x07
}

let vendor: [UInt8] = [0x00, 0x20, 0x0D]

/// A channel parameter in RME's 3-byte container: 4-bit address, 5-bit index, 12-bit signed value.
public struct ChannelParameter: Equatable, Sendable {
    public var address: Int
    public var index: Int
    public var value: Int

    public init(address: Int, index: Int, value: Int) {
        self.address = address
        self.index = index
        self.value = value
    }

    public var bytes: [UInt8] {
        let raw = value & 0xFFF
        return [
            UInt8((address << 3) | (index >> 2)),
            UInt8(((index & 0x3) << 5) | ((raw >> 7) & 0x1F)),
            UInt8(raw & 0x7F),
        ]
    }

    /// Decodes a channel container; nil for device (12) and EQ-preset (13, 14) addresses.
    public init?(_ b1: UInt8, _ b2: UInt8, _ b3: UInt8) {
        let address = Int(b1) >> 3
        guard address <= 11 else { return nil }
        let raw = ((Int(b2) & 0x1F) << 7) | Int(b3)
        self.address = address
        self.index = ((Int(b1) & 0x7) << 2) | (Int(b2) >> 5)
        self.value = raw >= 2048 ? raw - 4096 : raw
    }
}

public enum Message {
    /// "Send all settings": also makes the device start pushing changes and status.
    public static func requestAll(_ model: Model) -> [UInt8] {
        vendor + [model.rawValue, Command.request.rawValue, 0x09]
    }

    public static func set(_ model: Model, _ parameters: [ChannelParameter]) -> [UInt8] {
        vendor + [model.rawValue, Command.toDevice.rawValue] + parameters.flatMap(\.bytes)
    }

    public static func set(_ model: Model, _ output: Output, _ parameter: OutputParameter, _ value: Int) -> [UInt8] {
        set(model, [ChannelParameter(address: output.rawValue, index: parameter.rawValue, value: value)])
    }

    /// Channel parameters the device reports in a "send parameters to remote" message; empty for anything else.
    public static func parameters(in payload: [UInt8], model: Model) -> [ChannelParameter] {
        guard payload.count >= 5,
              Array(payload.prefix(3)) == vendor,
              payload[3] == model.rawValue,
              payload[4] == Command.toRemote.rawValue
        else { return [] }
        var result: [ChannelParameter] = []
        var i = 5
        while i + 2 < payload.count {
            if let p = ChannelParameter(payload[i], payload[i + 1], payload[i + 2]) { result.append(p) }
            i += 3
        }
        return result
    }
}

/// What the agent knows about one output. nil means not yet reported by the device.
public struct OutputState: Equatable, Sendable {
    public var volume: Int?
    public var muted: Bool?

    public init(volume: Int? = nil, muted: Bool? = nil) {
        self.volume = volume
        self.muted = muted
    }

    public mutating func apply(_ parameters: [ChannelParameter], for output: Output) {
        for p in parameters where p.address == output.rawValue {
            switch OutputParameter(rawValue: p.index) {
            case .volume: volume = p.value
            case .mute: muted = p.value != 0
            case nil: break
            }
        }
    }

    /// The volume after a step of `delta` tenths of a dB, clamped to the device range and `ceiling`.
    public func stepped(by delta: Int, ceiling: Int = Volume.max) -> Int? {
        guard let volume else { return nil }
        // A volume already above the ceiling (set on the device) stays put on up and steps normally on down.
        let top = Swift.max(Swift.min(ceiling, Volume.max), Swift.min(volume, Volume.max))
        return Swift.max(Volume.min, Swift.min(top, volume + delta))
    }
}
