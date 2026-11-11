#!/bin/zsh
# Signs dist/adi2keys.app (from release/build.sh) for release, optionally notarizes and staples it,
# and writes dist/adi2keys-<version>.zip.
#
# SIGN_IDENTITY   required, e.g. "Developer ID Application: Jesper Noehr (TEAMID)"
# NOTARY_PROFILE  notarytool keychain profile (see `xcrun notarytool store-credentials`);
#                 unset skips notarization
# KEYCHAIN        keychain holding the identity, if not the default
# SIGN_TIMESTAMP  "none" signs without a secure timestamp: for testing only, notarization needs one
set -euo pipefail
cd "${0:A:h}/.."
: "${SIGN_IDENTITY:?set SIGN_IDENTITY}"

[[ -d dist/adi2keys.app ]] || { echo "No dist/adi2keys.app: run release/build.sh first" >&2; exit 1 }
version=$(plutil -extract CFBundleShortVersionString raw dist/adi2keys.app/Contents/Info.plist)

out=dist/signed
rm -rf "$out"
mkdir -p "$out"
ditto dist/adi2keys.app "$out/adi2keys.app"

args=(--force --options runtime --sign "$SIGN_IDENTITY")
if [[ ${SIGN_TIMESTAMP:-} == none ]]; then args+=(--timestamp=none); else args+=(--timestamp); fi
[[ -n ${KEYCHAIN:-} ]] && args+=(--keychain "$KEYCHAIN")
codesign "${args[@]}" "$out/adi2keys.app"
codesign --verify --strict --deep "$out/adi2keys.app"

if [[ -n ${NOTARY_PROFILE:-} ]]; then
    ditto -c -k --keepParent "$out/adi2keys.app" "$out/notarize.zip"
    xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$out/adi2keys.app"
    rm "$out/notarize.zip"
fi

rm -f "dist/adi2keys-$version.zip"
(cd "$out" && ditto -c -k --keepParent adi2keys.app "../adi2keys-$version.zip")
(cd dist && shasum -a 256 "adi2keys-$version.zip")
