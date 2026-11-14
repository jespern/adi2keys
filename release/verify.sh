#!/bin/zsh
# Checks a published release against its source: verifies the signature, if any, rebuilds the git ref
# unsigned, and compares every file. Signed executables are compared after removing the signature
# (docs/REPRODUCIBLE-BUILDS.md). Needs the same Xcode version as the release (dist/toolchain.txt).
#
# Usage: release/verify.sh adi2keys-<version>.zip [git-ref]     (ref defaults to v<version>)
# TEAM_ID  if set, the signature must be a Developer ID Application certificate from this team
set -euo pipefail
repo=${0:A:h:h}
[[ $# -ge 1 ]] || { echo "usage: $0 <release.zip> [git-ref]" >&2; exit 2 }
release=${1:A}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1 }

mkdir "$tmp/published"
ditto -x -k "$release" "$tmp/published"
published=$tmp/published/adi2keys.app
[[ -d $published ]] || fail "no adi2keys.app in $release"
version=$(plutil -extract CFBundleShortVersionString raw "$published/Contents/Info.plist")
ref=${2:-v$version}

# 1. The signature is valid, and from the expected team. An unsigned release, such as the
#    ones published for shadybin to certify, has none to check.
signed=true
details=$(codesign -dvv "$published" 2>&1 || true)
if [[ $details == *"not signed at all"* ]]; then
    signed=false
    [[ -z ${TEAM_ID:-} ]] || fail "unsigned, but TEAM_ID asks for a Developer ID signature"
    authority="nobody (unsigned)"
else
    codesign --verify --strict --deep "$published" || fail "invalid signature"
fi
[[ $signed == true ]] && authority=$(print -r -- "$details" | sed -n 's/^Authority=//p' | head -1)
if [[ $signed == false ]]; then
    :
elif [[ -n ${TEAM_ID:-} ]]; then
    print -r -- "$details" | grep -qx "TeamIdentifier=$TEAM_ID" || fail "not signed by team $TEAM_ID"
    [[ $authority == "Developer ID Application:"* ]] || fail "not a Developer ID Application signature"
else
    echo "warning: TEAM_ID not set; signer not checked ($authority)" >&2
fi

# 2. Rebuild the ref, unsigned, from exactly the committed tree.
mkdir "$tmp/source"
git -C "$repo" archive "$ref" | tar -x -C "$tmp/source"
(cd "$tmp/source" && VERSION=$version SOURCE_DATE_EPOCH=0 zsh release/build.sh >/dev/null)
built=$tmp/source/dist/adi2keys.app

# 3. Same files, ignoring the signature and a stapled notarization ticket.
files() { (cd "$1" && find . -type f ! -path './Contents/_CodeSignature/*' ! -path './Contents/CodeResources' | LC_ALL=C sort) }
diff <(files "$published") <(files "$built") >&2 || fail "the release and the rebuild contain different files"

# 4. Same contents; executables compared without their signature.
for file in ${(f)"$(files "$built")"}; do
    if [[ $signed == true ]] && file -b "$built/$file" | grep -q Mach-O; then
        cp "$published/$file" "$tmp/stripped"
        codesign --remove-signature "$tmp/stripped"
        swift "$repo/release/normalize-linkedit.swift" "$tmp/stripped"
        cmp -s "$tmp/stripped" "$built/$file" || fail "$file differs from the rebuild"
    else
        cmp -s "$published/$file" "$built/$file" || fail "$file differs from the rebuild"
    fi
done

echo "OK: $release matches $ref, signed by $authority"
