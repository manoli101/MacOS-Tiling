#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in your login keychain.
# Run ONCE. After this, macOS will remember Accessibility permission across reinstalls
# because the certificate identity (not the binary hash) is used for TCC matching.
set -euo pipefail

CERT_NAME="MacOSTiling Dev"
KEYCHAIN=~/Library/Keychains/login.keychain-db

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" &>/dev/null; then
    echo "✅ Certificate '$CERT_NAME' already exists — nothing to do."
    exit 0
fi

echo "▶ Creating self-signed code-signing certificate..."

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

cat > "$TMPDIR/req.conf" << 'EOF'
[ req ]
default_bits       = 2048
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[ dn ]
CN = MacOSTiling Dev
[ ext ]
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
basicConstraints     = critical, CA:false
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMPDIR/key.pem" \
    -out "$TMPDIR/cert.pem" -days 3650 -nodes \
    -config "$TMPDIR/req.conf" 2>/dev/null

# Legacy algorithms required: OpenSSL 3.x defaults are incompatible with macOS security import
openssl pkcs12 -export -out "$TMPDIR/bundle.p12" \
    -inkey "$TMPDIR/key.pem" -in "$TMPDIR/cert.pem" \
    -passout pass:macos-tiling-tmp \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null

security import "$TMPDIR/bundle.p12" \
    -k "$KEYCHAIN" -P macos-tiling-tmp \
    -T /usr/bin/codesign 2>/dev/null || {
    echo "❌ Import failed. Make sure your login keychain is unlocked."
    exit 1
}

# Allow codesign to use the private key without prompting each time.
# macOS may ask for keychain password once — enter it and click Always Allow.
security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s -k "" -D "$CERT_NAME" -t private \
    "$KEYCHAIN" 2>/dev/null || true

# Trust the cert for code signing (required so AXIsProcessTrusted returns true)
CERT_PEM=$(mktemp /tmp/macos-tiling-cert.XXXXXX.pem)
security find-certificate -c "$CERT_NAME" -p "$KEYCHAIN" > "$CERT_PEM" 2>/dev/null
security add-trusted-cert -r trustRoot -k "$KEYCHAIN" "$CERT_PEM" 2>/dev/null || true
rm -f "$CERT_PEM"

echo ""
echo "✅ Certificate '$CERT_NAME' created and trusted."
echo ""
echo "Next: rebuild with  bash Scripts/build.sh"
echo "After that, grant Accessibility once — it will be remembered permanently."
