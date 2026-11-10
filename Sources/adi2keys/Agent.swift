import ADI2Protocol
import AppKit
import os

private let log = Logger(subsystem: "org.noehr.adi2keys", category: "agent")

/// Maps the volume keys to the hardware volume of an ADI-2 while it is the default output.
///
/// State comes from the device itself: on connect we request all settings, which also makes the
/// device push every later change (front-panel knob, ADI-2 Remote) and a status message about once
/// a second. Nothing here polls.
@MainActor
final class Agent {
    private let midi: MIDI
    private let defaultOutput = DefaultOutput()
    private let keys = KeyTap()
    private let defaults = UserDefaults.standard

    private var model: Model?
    private var state = OutputState()
    private var trackedOutput: Output?
    private var lastHeard: ContinuousClock.Instant?
    /// Key presses that arrived before the device reported its state.
    private var pendingDelta = 0
    private var pendingMuteToggle = false

    init() throws {
        midi = try MIDI()
        defaults.register(defaults: ["output": "line", "step": 1.0, "fineStep": 0.5, "maxVolume": 6.0])
    }

    func start() {
        midi.onSetupChanged = { [unowned self] in refresh() }
        midi.onSysEx = { [unowned self] in received($0) }
        defaultOutput.onChange = { [unowned self] in refresh() }
        keys.handler = { [unowned self] in handle($0) }
        refresh()
        keys.start()
    }

    // MARK: Settings, read on every use so `defaults write` applies without a restart

    private var output: Output {
        guard let name = defaults.string(forKey: "output"), let output = Output(name: name) else { return .line }
        return output
    }

    private func tenths(_ key: String) -> Int { Int((defaults.double(forKey: key) * 10).rounded()) }

    // MARK: Device tracking

    /// Picks the ADI-2 that is the default output, or failing that the first one present.
    private func refresh() {
        let ports = midi.ports()
        let defaultName = defaultOutput.name
        let port = ports.first { defaultName.map($0.name.hasPrefix) ?? false } ?? ports.first
        guard port != midi.connected else { return }
        midi.connect(port)
        model = port.flatMap { Model(deviceName: $0.name) }
        reset()
        if let port { log.notice("connected to \(port.name, privacy: .public)") } else { log.notice("no ADI-2 present") }
    }

    private func reset() {
        state = OutputState()
        trackedOutput = output
        lastHeard = nil
        pendingDelta = 0
        pendingMuteToggle = false
        if let model { midi.send(Message.requestAll(model)) }
    }

    private var isDefaultOutput: Bool {
        guard let connected = midi.connected, let name = defaultOutput.name else { return false }
        return connected.name.hasPrefix(name)
    }

    private func received(_ payload: [UInt8]) {
        guard let model, payload.count > 4, payload[3] == model.rawValue else { return }
        lastHeard = .now
        guard let output = trackedOutput else { return }
        state.apply(Message.parameters(in: payload, model: model), for: output)
        applyPending()
    }

    // MARK: Keys

    private func handle(_ press: MediaKeyPress) -> Bool {
        guard model != nil, isDefaultOutput else { return false }
        let modifiers = press.modifiers.intersection([.shift, .option, .control, .command])
        // Option alone opens Sound settings, as usual.
        if modifiers == .option { return false }
        guard press.isDown else { return true }

        // Output setting changed, or the device went quiet (power cycle, standby): resync first.
        let stale = lastHeard.map { .now - $0 > .seconds(3) } ?? true
        if output != trackedOutput || stale { reset() }

        switch press.key {
        case .volumeUp, .volumeDown:
            let step = tenths(modifiers == [.shift, .option] ? "fineStep" : "step")
            pendingDelta += press.key == .volumeUp ? step : -step
        case .mute:
            if !press.isRepeat { pendingMuteToggle.toggle() }
        }
        applyPending()
        return true
    }

    private func applyPending() {
        guard let model, let output = trackedOutput, pendingDelta != 0 || pendingMuteToggle,
              state.volume != nil, state.muted != nil
        else { return }
        var parameters: [ChannelParameter] = []
        if pendingDelta != 0, let volume = state.stepped(by: pendingDelta, ceiling: tenths("maxVolume")) {
            parameters.append(ChannelParameter(address: output.rawValue, index: OutputParameter.volume.rawValue, value: volume))
            state.volume = volume
            // Changing the volume unmutes, as macOS does.
            if state.muted == true && !pendingMuteToggle { pendingMuteToggle = true }
        }
        if pendingMuteToggle, let muted = state.muted {
            parameters.append(ChannelParameter(address: output.rawValue, index: OutputParameter.mute.rawValue, value: muted ? 0 : 1))
            state.muted = !muted
        }
        pendingDelta = 0
        pendingMuteToggle = false
        if !parameters.isEmpty { midi.send(Message.set(model, parameters)) }
    }
}
