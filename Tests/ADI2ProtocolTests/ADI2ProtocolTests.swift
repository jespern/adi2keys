import Testing
@testable import ADI2Protocol

// Byte sequences from RME's MIDITable_ADI-2 "Examples" sheet, and from a real ADI-2 Pro dump.

@Test func setPhones34VolumeMatchesRMEExample() {
    // "Set Volume of Phones 34 to -10dB (address 9, parameter index 12, value -100)"
    #expect(Message.set(.pro4, .phones34, .volume, -100) == [0x00, 0x20, 0x0D, 0x73, 0x02, 0x4B, 0x1F, 0x1C])
}

@Test func setInputRangeMatchesRMEExample() {
    // "Set Input-Range to 13dBu (address 0, parameter index 1, value 2)"
    #expect(Message.set(.pro4, [ChannelParameter(address: 0, index: 1, value: 2)]) == [0x00, 0x20, 0x0D, 0x73, 0x02, 0x00, 0x20, 0x02])
}

@Test func requestAllMatchesRMEExample() {
    #expect(Message.requestAll(.pro4) == [0x00, 0x20, 0x0D, 0x73, 0x03, 0x09])
}

@Test func lineOutVolumeAndMuteAddresses() {
    #expect(ChannelParameter(address: Output.line.rawValue, index: 12, value: -420).bytes == [0x1B, 0x1C, 0x5C])
    #expect(ChannelParameter(address: Output.line.rawValue, index: 15, value: 1).bytes == [0x1B, 0x60, 0x01])
    #expect(ChannelParameter(address: Output.phones12.rawValue, index: 12, value: 0).bytes == [0x33, 0x00, 0x00])
}

@Test(arguments: [Volume.min, -420, -100, -1, 0, 1, 35, Volume.max])
func containerRoundTrips(value: Int) {
    let bytes = ChannelParameter(address: 3, index: 12, value: value).bytes
    #expect(bytes.allSatisfy { $0 < 0x80 })
    #expect(ChannelParameter(bytes[0], bytes[1], bytes[2]) == ChannelParameter(address: 3, index: 12, value: value))
}

@Test func deviceParametersAreNotChannelParameters() {
    #expect(ChannelParameter(0x60, 0x60, 0x01) == nil)   // address 12
    #expect(ChannelParameter(0x68, 0x20, 0x10) == nil)   // address 13, EQ preset
}

@Test func parsesStateFromDump() {
    // Line out -42.0 dB unmuted, then phones 3/4 -10 dB, as an ADI-2 Pro reports them.
    let payload: [UInt8] = [0x00, 0x20, 0x0D, 0x72, 0x01, 0x1B, 0x1C, 0x5C, 0x1B, 0x60, 0x00, 0x4B, 0x1F, 0x1C, 0x60, 0x60, 0x01]
    var line = OutputState()
    line.apply(Message.parameters(in: payload, model: .pro), for: .line)
    #expect(line == OutputState(volume: -420, muted: false))
    var phones = OutputState()
    phones.apply(Message.parameters(in: payload, model: .pro), for: .phones34)
    #expect(phones == OutputState(volume: -100, muted: nil))
}

@Test func ignoresOtherDevicesAndCommands() {
    #expect(Message.parameters(in: [0x00, 0x20, 0x0D, 0x71, 0x01, 0x1B, 0x1C, 0x5C], model: .pro).isEmpty)
    #expect(Message.parameters(in: [0x00, 0x20, 0x0D, 0x72, 0x07, 0x05, 0x30, 0x7E], model: .pro).isEmpty)
}

@Test func steppingClampsAndKeepsUnknownUnknown() {
    #expect(OutputState().stepped(by: 10) == nil)
    #expect(OutputState(volume: -420).stepped(by: 10) == -410)
    #expect(OutputState(volume: 55).stepped(by: 10) == Volume.max)
    #expect(OutputState(volume: -1140).stepped(by: -10) == Volume.min)
    #expect(OutputState(volume: -5).stepped(by: 10, ceiling: 0) == 0)
    #expect(OutputState(volume: 30).stepped(by: 10, ceiling: 0) == 30)
    #expect(OutputState(volume: 30).stepped(by: -10, ceiling: 0) == 20)
}

@Test func modelFromName() {
    #expect(Model(deviceName: "ADI-2 Pro (56011377)") == .pro)
    #expect(Model(deviceName: "ADI-2 Pro (56011377) Port 1") == .pro)
    #expect(Model(deviceName: "ADI-2 DAC (12345)") == .dac)
    #expect(Model(deviceName: "ADI-2/4 Pro SE (1)") == .pro4)
    #expect(Model(deviceName: "MacBook Pro Speakers") == nil)
}
