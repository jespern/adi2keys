# Reproducible, properly signed builds

Notes for publishing binary releases that anyone can check against the source, for example so
shadybin can certify them. Nothing here is wired up yet; releases are source-only for now.

Measured on 2026-11-10 with Xcode 27.2 (27B52), Swift 6.4.2, on macOS 27.2, arm64.

## The approach

A Developer ID signature can never be reproduced: it contains a signing time and the secure
timestamp notarization requires, so signing the same binary twice gives different bytes. So the
signature is kept out of the comparison:

1. **Build unsigned and reproducibly.** The same source and toolchain give the same bytes,
   wherever the checkout is.
2. **Sign and notarize that exact build** for release, with the Developer ID.
3. **Verify** by checking the signature is valid and comes from the expected Developer ID, then
   stripping it off and comparing with an independent unsigned rebuild.

Bitcoin Core does the same for its macOS releases (deterministic unsigned build, with the
signature published and checked separately).

## 1. Reproducible unsigned build

```sh
swift build -c release --product adi2keys -Xlinker -S -Xlinker -no_adhoc_codesign
```

- Without flags, builds at the **same** path are byte-identical, but builds at different paths
  are not: the linker writes absolute paths to source and object files into the binary's debug
  map (`SO`/`OSO`/`N_AST` stab symbols), and the Mach-O UUID is computed over them.
- `-Xlinker -S` leaves the debug map out, which makes the build path-independent: two clones at
  different paths gave identical binaries, UUID included. **Trade-off:** no dSYM can be produced
  from such a binary, so crash reports can't be symbolicated. Fine for a tool this size.
- Things that did **not** work: `-Xswiftc -gnone` (SwiftPM's own `-g` wins; no change), and
  `-file-prefix-map` with `-oso_prefix` (paths in the module's `N_AST` entry and one object file
  survive). `strip -S` after linking removes the paths but not their effect on the UUID.
- `-Xlinker -no_adhoc_codesign` stops the linker adding its own ad-hoc signature, so the unsigned
  build is the true baseline for step 3.
- The exact Xcode version is part of the input: record it with each release. Different compiler
  versions produce different code.

## 2. Signing the release

```sh
codesign --force --options runtime --timestamp --sign "Developer ID Application: …" adi2keys.app
```

Then notarize. Not yet tested here: it needs a paid Apple Developer account.

## 3. Verifying a release

1. `codesign --verify --strict --deep adi2keys.app`, and check the `Authority=` chain names the
   expected Developer ID.
2. Copy the published executable, run `codesign --remove-signature` on the copy, then normalise it
   (see below).
3. Compare it byte for byte with the executable from an unsigned rebuild of the tag (step 1).
4. Compare the bundle's other files (`Info.plist`) directly. `Contents/_CodeSignature` is part of
   the signature and is excluded.

**Normalising.** `--remove-signature` leaves exactly one field different from a never-signed
binary: the `__LINKEDIT` segment's `vmsize` stays enlarged to fit the removed signature. Unsigned,
it is the segment's `filesize` rounded up to the 16 KB page size. Resetting it to that value made a
signed, stripped binary byte-identical to an unsigned rebuild from another checkout path. That was
checked with a throwaway self-signed certificate, hardened runtime on and no timestamp; a Developer
ID signature is larger but should leave the same single field.

```python
# Resets __LINKEDIT vmsize to its unsigned value. 64-bit Mach-O only.
import struct, sys
path = sys.argv[1]
data = bytearray(open(path, 'rb').read())
magic, _, _, _, ncmds, _, _, _ = struct.unpack_from('<IiiIIIII', data, 0)
assert magic == 0xFEEDFACF, 'not a 64-bit Mach-O'
off = 32
for _ in range(ncmds):
    cmd, size = struct.unpack_from('<II', data, off)
    if cmd == 0x19 and data[off+8:off+24].rstrip(b'\0') == b'__LINKEDIT':   # LC_SEGMENT_64
        filesize = struct.unpack_from('<Q', data, off + 48)[0]
        struct.pack_into('<Q', data, off + 32, -(-filesize // 0x4000) * 0x4000)
    off += size
open(path, 'wb').write(data)
```

## Open questions

- **Developer ID and notarization:** confirm the strip-and-normalise check with a real Developer
  ID signature and a secure timestamp.
- **Stapled notarization ticket:** stapling adds data to the bundle. Either verifiers exclude it,
  or the release isn't stapled and Gatekeeper fetches the ticket online.
- **Universal binary:** an arm64 + x86_64 build needs the same check on both slices (`lipo`).
- **CI runners:** GitHub-hosted runners must offer macOS 27 with Xcode 27.2 for a rebuild there.
- **shadybin:** supports only Go, Zig and Rust. Swift support would mean the unsigned rebuild
  above, plus a "strip and normalise" step for signed Mach-O files when comparing.
