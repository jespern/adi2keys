# Reproducible, properly signed builds

How to publish binary releases that anyone can check against the source, for example so shadybin
can certify them. Releases are source-only for now; the scripts in `release/` are ready apart from
the parts that need an Apple Developer account (marked below).

Measured on 2026-11-10/11 with Xcode 27.2 (27B52), Swift 6.4.2, on macOS 27.2. macOS 27 runs only on
Apple silicon, so releases are arm64 only.

## Making a release

```sh
git tag v0.2.0                     # the version comes from the tag
release/build.sh                   # dist/adi2keys.app, dist/adi2keys-0.2.0-unsigned.zip, dist/toolchain.txt
SIGN_IDENTITY="Developer ID Application: Jesper Noehr (TEAMID)" NOTARY_PROFILE=adi2keys release/sign.sh
TEAM_ID=TEAMID release/verify.sh dist/adi2keys-0.2.0.zip     # rebuilds v0.2.0 elsewhere and compares
```

Publish `dist/adi2keys-<version>.zip` and the Xcode version from `dist/toolchain.txt`.
`NOTARY_PROFILE` is a stored notarytool login: `xcrun notarytool store-credentials adi2keys`.

### Tested so far

With a throwaway self-signed certificate in a temporary keychain standing in for the Developer ID
(hardened runtime on, no timestamp, no notarization):

- `build.sh` from two checkouts at different paths: byte-identical zips, not just binaries.
- `verify.sh` on a release signed from one path, rebuilt by `git archive` of the ref at another: OK.
- Wrong `TEAM_ID`: fails ("not signed by team").
- One byte changed in the executable, then re-signed with the same key: fails ("differs from the
  rebuild"). A valid signature alone is not enough; the code must match the source.

### Needs the Developer account (untested)

- Signing with a real Developer ID certificate and a secure timestamp (`--timestamp`).
- Notarization and stapling. `verify.sh` ignores `Contents/CodeResources`, which is where I expect
  the stapler to put the ticket in an app bundle; confirm with a real stapled release.

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

`release/sign.sh` copies the unsigned app, signs it with hardened runtime and a secure timestamp,
and notarizes and staples it when `NOTARY_PROFILE` is set:

```sh
codesign --force --options runtime --timestamp --sign "Developer ID Application: …" adi2keys.app
```

## 3. Verifying a release

`release/verify.sh` does all of this:

1. `codesign --verify --strict --deep` on the published app, and with `TEAM_ID` set, checks the
   signature is a Developer ID Application certificate from that team.
2. Rebuilds the git ref with `release/build.sh`, from `git archive` of the ref (only committed
   files, nothing from the working tree).
3. Checks both bundles have the same files, ignoring `Contents/_CodeSignature` (the signature) and
   `Contents/CodeResources` (where a stapled ticket goes).
4. Compares each file byte for byte. Executables are compared after `codesign --remove-signature`
   and normalising (below).

**Normalising.** `--remove-signature` leaves exactly one field different from a never-signed
binary: the `__LINKEDIT` segment's `vmsize` stays enlarged to fit the removed signature. Unsigned,
it is the segment's `filesize` rounded up to the 16 KB page size; `release/normalize-linkedit.swift`
resets it to that. A Developer ID signature is larger than the test one but should leave the same
single field.

## Open questions

- **Developer ID and notarization:** see "Needs the Developer account" above.
- **CI runners:** GitHub-hosted runners must offer macOS 27 with Xcode 27.2 for a rebuild there.
- **shadybin:** supports only Go, Zig and Rust. Swift support would mean the unsigned rebuild
  above, plus a "strip and normalise" step for signed Mach-O files when comparing.
