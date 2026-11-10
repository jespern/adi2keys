#!/bin/zsh
# Builds adi2keys.app, installs it to ~/Applications and (re)starts it.
set -euo pipefail
cd "${0:A:h}"

swift build -c release --quiet
app=build/adi2keys.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/adi2keys" "$app/Contents/MacOS/"

plist="$app/Contents/Info.plist"
plutil -create xml1 "$plist"
plutil -insert CFBundleIdentifier -string org.noehr.adi2keys "$plist"
plutil -insert CFBundleName -string adi2keys "$plist"
plutil -insert CFBundleExecutable -string adi2keys "$plist"
plutil -insert CFBundlePackageType -string APPL "$plist"
plutil -insert CFBundleShortVersionString -string 0.1.0 "$plist"
plutil -insert LSMinimumSystemVersion -string 27.0 "$plist"
plutil -insert LSUIElement -bool true "$plist"

# A stable identity keeps the Accessibility grant across rebuilds (see make-signing-identity.sh);
# ad-hoc signatures change with every build.
identity="adi2keys local signing"
if security find-certificate -c "$identity" >/dev/null 2>&1; then
    codesign --force --sign "$identity" "$app"
else
    echo "No \"$identity\" certificate: signing ad hoc. Run ./make-signing-identity.sh to keep permissions across rebuilds."
    codesign --force --sign - "$app"
fi

pkill -x adi2keys || true
mkdir -p ~/Applications
rm -rf ~/Applications/adi2keys.app
cp -R "$app" ~/Applications/
open ~/Applications/adi2keys.app
echo "Installed ~/Applications/adi2keys.app"
