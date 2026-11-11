#!/bin/zsh
# Builds adi2keys.app with release/build.sh, signs it for this Mac, installs it to ~/Applications
# and (re)starts it.
set -euo pipefail
cd "${0:A:h}"

zsh release/build.sh >/dev/null
rm -rf build
mkdir -p build
ditto dist/adi2keys.app build/adi2keys.app
app=build/adi2keys.app

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
