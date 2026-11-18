#!/bin/bash
# Ensure a stable local codesigning identity for OneBox.
# Ad-hoc signatures change CDHash every rebuild and invalidate Screen Recording TCC;
# a fixed self-signed identity keeps permission across package/reload cycles.
#
# Usage:
#   ./Scripts/ensure-codesign-identity.sh          # print identity common name
#   ./Scripts/ensure-codesign-identity.sh --check  # exit 0 only if identity exists
set -euo pipefail

CERT_NAME="OneBox Local"
# PKCS12 import passphrase (not the login keychain password). Local-dev only.
P12_PASS="${ONEBOX_CODESIGN_P12_PASS:-onebox-local}"
KEYCHAIN="${ONEBOX_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

identity_exists() {
  security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null \
    | grep -F "\"$CERT_NAME\"" >/dev/null 2>&1
}

if [[ "${1:-}" == "--check" ]]; then
  if identity_exists; then
    echo "$CERT_NAME"
    exit 0
  fi
  echo "missing codesigning identity: $CERT_NAME" >&2
  exit 1
fi

if identity_exists; then
  echo "$CERT_NAME"
  exit 0
fi

echo "==> creating local codesigning certificate: $CERT_NAME" >&2

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

cat > "$TMP_DIR/openssl.cnf" <<EOF
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = v3_codesign

[req_distinguished_name]
CN = $CERT_NAME
O = OneBox
C = CN

[v3_codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
  -config "$TMP_DIR/openssl.cnf" \
  -keyout "$TMP_DIR/cert.key" \
  -out "$TMP_DIR/cert.crt" >/dev/null 2>&1

# OpenSSL 3 defaults are rejected by macOS SecKeychainItemImport; use legacy PBE.
openssl pkcs12 -export \
  -inkey "$TMP_DIR/cert.key" \
  -in "$TMP_DIR/cert.crt" \
  -out "$TMP_DIR/cert.p12" \
  -passout "pass:$P12_PASS" \
  -name "$CERT_NAME" \
  -certpbe PBE-SHA1-3DES \
  -keypbe PBE-SHA1-3DES \
  -macalg sha1 >/dev/null 2>&1

security import "$TMP_DIR/cert.p12" \
  -k "$KEYCHAIN" \
  -P "$P12_PASS" \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productsign >/dev/null

# Self-signed leaf must be trusted for codeSign or find-identity reports 0 valid.
security add-trusted-cert -d -r trustRoot -p codeSign \
  -k "$KEYCHAIN" "$TMP_DIR/cert.crt" >/dev/null

# Allow codesign to use the private key without keychain UI prompts when possible.
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "" \
  "$KEYCHAIN" >/dev/null 2>&1 || true

if ! identity_exists; then
  echo "error: imported certificate but codesigning identity \"$CERT_NAME\" not found" >&2
  echo "hint: Keychain Access → $CERT_NAME → Trust → Code Signing → Always Trust" >&2
  exit 1
fi

echo "$CERT_NAME"
