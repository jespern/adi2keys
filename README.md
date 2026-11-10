# adi2keys

Makes the Mac volume keys control the hardware volume of an RME ADI-2 (DAC, Pro, 2/4 Pro) over USB.

The ADI-2 exposes no CoreAudio volume control, so macOS's volume keys do nothing while it is the
default output. adi2keys catches the volume keys and sends the device's own MIDI SysEx volume and
mute commands, but only while an ADI-2 is the default output. Otherwise the keys pass through.

- Volume up/down: 1 dB steps. Shift+Option: 0.5 dB steps. Option alone still opens Sound settings.
- Mute toggles the output's mute. Changing the volume unmutes, as macOS does.
- Volume changes from the front-panel knob or ADI-2 Remote are tracked from the device's own change
  messages, so presses always step from the real value. ADI-2 Remote can run alongside.
- The ADI-2's display shows the volume screen on each change. There is no on-screen HUD on the Mac.

Requires "MIDI Control" on in the device's settings (it is, if ADI-2 Remote works).

## Install

    ./install.sh

This builds `adi2keys.app`, installs it to `~/Applications`, starts it, and registers it as a login
item. On first launch, grant it Accessibility access in System Settings > Privacy & Security >
Accessibility. The app is ad-hoc signed, so after a rebuild remove and re-grant that permission.

## Settings

Read on every key press, so changes apply immediately:

    defaults write org.noehr.adi2keys output line      # line (default), phones12, phones34
    defaults write org.noehr.adi2keys step 1.0         # dB per press
    defaults write org.noehr.adi2keys fineStep 0.5     # dB per Shift+Option press
    defaults write org.noehr.adi2keys maxVolume 6.0    # ceiling in dB for volume up (device max +6.0)

## Protocol

RME's MIDI protocol table: https://www.rme-audio.de/downloads/adi2remote_midi_protocol.zip
(`MIDITable_ADI-2_*.ods`). Volume is output-channel parameter 12 (0.1 dB, 12-bit signed) and mute is
parameter 15, on channel address 3 (line), 6 (phones 1/2) or 9 (phones 3/4). `Sources/ADI2Protocol`
implements the encoding; its tests use the byte sequences from RME's examples.

Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "org.noehr.adi2keys"'`
