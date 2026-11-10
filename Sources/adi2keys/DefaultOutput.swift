import CoreAudio
import Foundation

/// The system's default output device, with a callback when it changes.
@MainActor
final class DefaultOutput {
    var onChange: () -> Void = {}

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.onChange() }
        }
    }

    /// The default output device's name, e.g. "ADI-2 Pro (56011377)".
    var name: String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown
        else { return nil }

        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) {
            AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &size, $0)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
