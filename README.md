# adi2keys

[![shadybin](https://img.shields.io/endpoint?url=https://shadybin.dev/registry/github.com/jespern/adi2keys/badge.json)](https://shadybin.dev/registry/github.com/jespern/adi2keys/)

Make the Mac's volume keys control the hardware volume of an RME ADI-2 DAC, ADI-2 Pro or
ADI-2/4 Pro connected over USB.

When an ADI-2 is the Mac's output, the volume keys do nothing: the ADI-2 has no volume control
that macOS can use, so the volume HUD just shows the "unavailable" icon. The ADI-2 does accept
volume commands over its USB MIDI port; that's how RME's ADI-2 Remote app works. adi2keys is a
small background app that catches the volume and mute keys while an ADI-2 is the default output
and sends the ADI-2 the matching volume commands. With any other output selected, the keys work
as usual.

- **Volume up/down:** 1 dB per press, or 0.5 dB with Shift+Option. Option on its own still opens
  Sound settings.
- **Mute:** toggles mute on the output. Changing the volume unmutes, as it does on macOS.
- **Stays in sync:** volume changes from the front-panel knob or ADI-2 Remote arrive as messages
  from the device, so each key press steps from the real current value. ADI-2 Remote can keep
  running alongside.
- **Feedback:** the ADI-2's display shows its volume screen on each change. There is no on-screen
  HUD on the Mac.

Event-driven throughout: no polling, no dependencies beyond Apple's frameworks.

## Status

Verified with an ADI-2 Pro EX on macOS 27, controlling the line output. The
ADI-2 DAC and ADI-2/4 Pro use the same protocol and should work, but are untested; reports welcome.

## Requirements

- macOS 27 and Xcode 27 (Swift 6.4), to build from source.
- **MIDI Control** enabled in the ADI-2's settings. If ADI-2 Remote works, it is.

## Install

```sh
git clone https://github.com/jespern/adi2keys.git
cd adi2keys
./make-signing-identity.sh   # once per Mac; see Signing below
./install.sh
```

`install.sh` builds `adi2keys.app`, installs it to `~/Applications`, starts it, and registers it
to open at login. It has no Dock icon or menu-bar item.

On first launch macOS asks for permission to control the Mac: open **System Settings ›
Privacy & Security › Device Control and Data Access** and turn on **adi2keys**. The keys work
within a second of granting it; no relaunch is needed. adi2keys needs this permission to see and
intercept the volume keys; it doesn't look at any other input.

### Signing

macOS ties that permission to the app's code signature. `make-signing-identity.sh` creates a
self-signed certificate, "adi2keys local signing", in your login keychain. It stays on your Mac
and is used only to sign your own builds. `install.sh` signs with it, so the permission survives
rebuilds and updates.

Without the certificate, builds are signed ad hoc and every rebuild looks like a new app to
macOS. After each one, run `tccutil reset Accessibility org.noehr.adi2keys`, then grant the
permission again.

## Settings

Changes apply on the next key press; there is nothing to restart.

```sh
defaults write org.noehr.adi2keys output line      # line (default), phones12, phones34
defaults write org.noehr.adi2keys step 1.0         # dB per press
defaults write org.noehr.adi2keys fineStep 0.5     # dB per Shift+Option press
defaults write org.noehr.adi2keys maxVolume 6.0    # highest volume the keys go to, in dB (device max +6.0)
```

`defaults delete org.noehr.adi2keys <key>` restores a default.

## Uninstall

```sh
./uninstall.sh
```

This stops the app, removes it from `~/Applications` and from the login items, and clears its
permission and settings. The signing certificate is kept; delete "adi2keys local signing" in
Keychain Access if you don't want it.

## Troubleshooting

The logs show what the app sees:

```sh
/usr/bin/log show --last 10m --predicate 'subsystem == "org.noehr.adi2keys"'
```

- **"waiting for Accessibility permission"**: grant the permission as described above.
- **"no ADI-2 present"**: the ADI-2's MIDI port isn't visible. Check the USB connection and that
  MIDI Control is on.
- **Keys do nothing, no errors**: check the ADI-2 is the default output in Sound settings.
  adi2keys leaves the keys alone for any other output.

## How it works

RME publishes the ADI-2 MIDI protocol as a spreadsheet in
[adi2remote_midi_protocol.zip](https://www.rme-audio.de/downloads/adi2remote_midi_protocol.zip).
Parameters travel as SysEx messages in 3-byte containers. Volume is output parameter 12 (a 12-bit
signed value in 0.1 dB steps, −114.5 to +6.0 dB) and mute is parameter 15, on channel address 3
(line out), 6 (phones 1/2) or 9 (phones 3/4).

On connect, adi2keys asks the device for all its settings. After that the device sends every
change on its own, so adi2keys always knows the current volume without asking again.
[`Sources/ADI2Protocol`](Sources/ADI2Protocol) has the encoding; its tests check it against the
byte sequences in RME's examples.

```sh
swift test
```

## Releases

Each release tag publishes an unsigned build, `adi2keys-<version>-unsigned.zip`, which
[shadybin](https://shadybin.dev) certifies: it rebuilds the tag sealed, offline and from the
reviewed source alone, checks the result is byte for byte the published zip, and has the code
reviewed. macOS will not open the unsigned app without approval, so to use adi2keys, build it
from source as above; the release is there to check against. `release/verify.sh` checks a
release yourself, and `docs/REPRODUCIBLE-BUILDS.md` explains how the build is made reproducible.

## License

MIT; see [LICENSE](LICENSE).

## Disclaimer

Not affiliated with or endorsed by RME. RME and ADI-2 are trademarks of their respective owners.
