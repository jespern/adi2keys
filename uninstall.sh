#!/bin/zsh
# Removes adi2keys: the app, its login item, its permission grant and its settings.
# Keeps the "adi2keys local signing" certificate; delete it in Keychain Access if unwanted.
set -uo pipefail

app=~/Applications/adi2keys.app

pkill -x adi2keys
[[ -x "$app/Contents/MacOS/adi2keys" ]] && "$app/Contents/MacOS/adi2keys" --unregister-login-item
rm -rf "$app"
tccutil reset Accessibility org.noehr.adi2keys >/dev/null
defaults delete org.noehr.adi2keys >/dev/null 2>&1
echo "Removed adi2keys"
