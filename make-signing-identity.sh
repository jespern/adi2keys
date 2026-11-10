#!/bin/zsh
# Creates a self-signed code-signing identity in the login keychain, so builds keep the same
# signature and macOS keeps the Accessibility grant across rebuilds. Local only; run once per Mac.
set -euo pipefail

name="adi2keys local signing"
if security find-certificate -c "$name" >/dev/null 2>&1; then
    echo "\"$name\" already exists"
    exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
pass=$(openssl rand -hex 16)

cat > "$dir/cert.conf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.conf" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$dir/key.pem" -in "$dir/cert.pem" \
    -name "$name" -passout "pass:$pass" -out "$dir/identity.p12" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" \
    -name "$name" -passout "pass:$pass" -out "$dir/identity.p12"

# -T lets codesign use the key without a keychain prompt on every build.
security import "$dir/identity.p12" -k ~/Library/Keychains/login.keychain-db -P "$pass" -T /usr/bin/codesign
echo "Created \"$name\""
