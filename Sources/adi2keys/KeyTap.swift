import AppKit
import ApplicationServices
import os

private let log = Logger(subsystem: "org.noehr.adi2keys", category: "keys")

struct MediaKeyPress: Sendable {
    enum Key { case volumeUp, volumeDown, mute }
    var key: Key
    var isDown: Bool
    var isRepeat: Bool
    var modifiers: NSEvent.ModifierFlags
}

/// Event tap for the media volume keys. The handler returns true to swallow the event.
/// Needs Accessibility permission; retries when the permission list changes.
@MainActor
final class KeyTap {
    var handler: (MediaKeyPress) -> Bool = { _ in false }
    private var tap: CFMachPort?
    private var permissionTimer: Timer?
    private var permissionChecksLeft = 0

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The notification can arrive before the permission takes effect: try now and once more shortly after.
            MainActor.assumeIsolated { self?.install() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { self?.install() } }
        }
        let prompt = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(prompt) {
            log.notice("waiting for Accessibility permission")
            awaitPermission()
        }
        install()
    }

    /// macOS 27 doesn't reliably post the notification above when access is granted, so while
    /// waiting at startup, check once a second for up to two minutes. Never runs once the tap exists.
    private func awaitPermission() {
        permissionChecksLeft = 120
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPermission() }
        }
    }

    private func checkPermission() {
        permissionChecksLeft -= 1
        install()
        guard tap == nil else { return }
        if permissionChecksLeft <= 0 {
            log.notice("still no Accessibility permission; relaunch after granting it")
            stopAwaitingPermission()
        }
    }

    private func stopAwaitingPermission() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func install() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            log.error("event tap creation failed")
            return
        }
        self.tap = tap
        stopAwaitingPermission()
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        log.notice("volume keys active")
    }

    fileprivate func handle(_ type: CGEventType, _ press: MediaKeyPress?) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard let press else { return false }
        return handler(press)
    }
}

private func keyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let press = mediaKeyPress(type, event)
    let keyTap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated { keyTap.handle(type, press) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

private func mediaKeyPress(_ type: CGEventType, _ event: CGEvent) -> MediaKeyPress? {
    guard type.rawValue == NSEvent.EventType.systemDefined.rawValue,
          let nsEvent = NSEvent(cgEvent: event),
          nsEvent.subtype.rawValue == 8   // NX_SUBTYPE_AUX_CONTROL_BUTTONS
    else { return nil }
    let data = nsEvent.data1
    let key: MediaKeyPress.Key
    switch (data & 0xFFFF_0000) >> 16 {
    case 0: key = .volumeUp      // NX_KEYTYPE_SOUND_UP
    case 1: key = .volumeDown    // NX_KEYTYPE_SOUND_DOWN
    case 7: key = .mute          // NX_KEYTYPE_MUTE
    default: return nil
    }
    let flags = data & 0xFFFF
    return MediaKeyPress(
        key: key,
        isDown: (flags & 0xFF00) >> 8 == 0xA,
        isRepeat: flags & 0x1 != 0,
        modifiers: nsEvent.modifierFlags.intersection(.deviceIndependentFlagsMask))
}
