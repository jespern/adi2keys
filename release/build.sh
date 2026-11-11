#!/bin/zsh
# Builds the unsigned, reproducible app: dist/adi2keys.app and dist/adi2keys-<version>-unsigned.zip.
# The same source and Xcode give the same bytes wherever the checkout is (docs/REPRODUCIBLE-BUILDS.md).
#
# VERSION            defaults to the exact tag on HEAD (without "v"), else 0.0.0-dev
# SOURCE_DATE_EPOCH  timestamp for files in the zip; defaults to the HEAD commit time
set -euo pipefail
cd "${0:A:h}/.."

version=${VERSION:-$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//' || true)}
version=${version:-0.0.0-dev}
epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}

# -S: no debug map, whose absolute paths would make the build depend on the checkout path.
# -no_adhoc_codesign: no linker signature, so the unsigned binary is the baseline for verification.
swift build -c release --product adi2keys --quiet -Xlinker -S -Xlinker -no_adhoc_codesign
bin="$(swift build -c release --show-bin-path)/adi2keys"

rm -rf dist
app=dist/adi2keys.app
mkdir -p "$app/Contents/MacOS"
cp "$bin" "$app/Contents/MacOS/adi2keys"

plist="$app/Contents/Info.plist"
plutil -create xml1 "$plist"
plutil -insert CFBundleIdentifier -string org.noehr.adi2keys "$plist"
plutil -insert CFBundleName -string adi2keys "$plist"
plutil -insert CFBundleExecutable -string adi2keys "$plist"
plutil -insert CFBundlePackageType -string APPL "$plist"
plutil -insert CFBundleShortVersionString -string "$version" "$plist"
plutil -insert CFBundleVersion -string "$version" "$plist"
plutil -insert LSMinimumSystemVersion -string 27.0 "$plist"
plutil -insert LSUIElement -bool true "$plist"

# Normalise everything the zip records besides content: permissions, xattrs, times, order.
chmod -R u=rwX,go=rX "$app"
xattr -cr "$app"
stamp=$(TZ=UTC date -r "$epoch" +%Y%m%d%H%M.%S)
find "$app" -exec env TZ=UTC touch -h -t "$stamp" {} +
(cd dist && find adi2keys.app | LC_ALL=C sort | TZ=UTC zip -X -q -@ "adi2keys-$version-unsigned.zip")

xcodebuild -version | tr '\n' ' ' | sed 's/ *$//' > dist/toolchain.txt
echo >> dist/toolchain.txt
(cd dist && shasum -a 256 "adi2keys-$version-unsigned.zip")
