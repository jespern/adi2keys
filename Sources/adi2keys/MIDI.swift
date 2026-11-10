import CoreMIDI
import Foundation
import Synchronization
import os

private let log = Logger(subsystem: "org.noehr.adi2keys", category: "midi")

/// CoreMIDI client for ADI-2 devices: finds their ports, sends SysEx, and delivers
/// reassembled incoming SysEx payloads (without F0/F7) on the main queue.
@MainActor
final class MIDI {
    struct Port: Equatable {
        var name: String
        var source: MIDIEndpointRef
        var destination: MIDIEndpointRef
    }

    var onSetupChanged: () -> Void = {}
    var onSysEx: ([UInt8]) -> Void = { _ in }

    private var client = MIDIClientRef()
    private var input = MIDIPortRef()
    private var output = MIDIPortRef()
    private(set) var connected: Port?

    init() throws {
        // The CoreMIDI callbacks below run on CoreMIDI threads, so they must not inherit this class's main-actor isolation.
        var status = MIDIClientCreateWithBlock("adi2keys" as CFString, &client) { @Sendable [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onSetupChanged() } }
        }
        guard status == noErr else { throw MIDIError(status: status, call: "MIDIClientCreate") }

        let assembler = SysExAssembler()
        status = MIDIInputPortCreateWithProtocol(client, "in" as CFString, ._1_0, &input) { @Sendable [weak self] list, _ in
            let messages = assembler.consume(list)
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { messages.forEach { self?.onSysEx($0) } } }
        }
        guard status == noErr else { throw MIDIError(status: status, call: "MIDIInputPortCreate") }

        status = MIDIOutputPortCreate(client, "out" as CFString, &output)
        guard status == noErr else { throw MIDIError(status: status, call: "MIDIOutputPortCreate") }
    }

    /// ADI-2 ports currently present, matched by name ("ADI-2 Pro (56011377) Port 1").
    func ports() -> [Port] {
        let sources = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource)
        let destinations = (0..<MIDIGetNumberOfDestinations()).map(MIDIGetDestination)
        return sources.compactMap { source in
            let name = displayName(source)
            guard name.hasPrefix("ADI-2"),
                  let destination = destinations.first(where: { displayName($0) == name })
            else { return nil }
            return Port(name: name, source: source, destination: destination)
        }
    }

    func connect(_ port: Port?) {
        guard port != connected else { return }
        if let connected { MIDIPortDisconnectSource(input, connected.source) }
        connected = port
        guard let port else { return }
        let status = MIDIPortConnectSource(input, port.source, nil)
        if status != noErr { log.error("connect source failed: \(status)") }
    }

    func send(_ payload: [UInt8]) {
        guard let connected else { return }
        // A SysEx7 UMP carries up to 6 bytes; longer payloads use start/continue/end packets.
        let chunks = stride(from: 0, to: payload.count, by: 6).map { Array(payload[$0..<min($0 + 6, payload.count)]) }
        let bufferSize = 64 + chunks.count * 16
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet = MIDIEventListInit(list, ._1_0)
        for (i, chunk) in chunks.enumerated() {
            let kind: UInt32 = chunks.count == 1 ? 0 : i == 0 ? 1 : i == chunks.count - 1 ? 3 : 2
            let b = chunk + Array(repeating: 0, count: 6 - chunk.count)
            var words: [UInt32] = [
                0x3 << 28 | kind << 20 | UInt32(chunk.count) << 16 | UInt32(b[0]) << 8 | UInt32(b[1]),
                UInt32(b[2]) << 24 | UInt32(b[3]) << 16 | UInt32(b[4]) << 8 | UInt32(b[5]),
            ]
            packet = MIDIEventListAdd(list, bufferSize, packet, 0, 2, &words)
        }
        let status = MIDISendEventList(output, connected.destination, list)
        if status != noErr { log.error("send failed: \(status)") }
    }

    private func displayName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name) == noErr, let name else { return "" }
        return name.takeRetainedValue() as String
    }
}

struct MIDIError: Error, CustomStringConvertible {
    var status: OSStatus
    var call: String
    var description: String { "\(call) failed: \(status)" }
}

/// Reassembles SysEx7 UMP packets into complete payloads. Called only from CoreMIDI's receive thread,
/// but the closure that owns it must be Sendable, hence the Mutex.
private final class SysExAssembler: Sendable {
    private let buffer = Mutex<[UInt8]>([])

    func consume(_ list: UnsafePointer<MIDIEventList>) -> [[UInt8]] {
        var complete: [[UInt8]] = []
        buffer.withLock { buffer in
            for packet in list.unsafeSequence() {
                let words = packet.words()
                var i = 0
                while i + 1 < words.count {
                    let w0 = words[i], w1 = words[i + 1]
                    i += 2
                    guard w0 >> 28 == 0x3 else { continue }
                    let kind = (w0 >> 20) & 0xF
                    let count = min(Int((w0 >> 16) & 0xF), 6)
                    let bytes = [w0 >> 8, w0, w1 >> 24, w1 >> 16, w1 >> 8, w1].map { UInt8(truncatingIfNeeded: $0) }
                    if kind == 0 || kind == 1 { buffer.removeAll(keepingCapacity: true) }
                    buffer += bytes.prefix(count)
                    if kind == 0 || kind == 3 { complete.append(buffer) }
                }
            }
        }
        return complete
    }
}
