#!/usr/bin/env bash
# One-time: creates the self-signed code signing identity used for every build
# (PDR §7.1), imports it into the login keychain and trusts it for code signing.
#
# Idempotent: exits 0 if the identity is already valid. If the certificate was
# imported earlier but never trusted, only the trust step runs.
#
# Nothing is written outside a temp dir (wiped on exit) and the login keychain.
# macOS asks for your login password once to add the trust setting.
set -euo pipefail

IDENTITY="OmniWM Extension Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
DAYS=3650
OPENSSL="${OPENSSL:-openssl}"

has_valid_identity() {
  security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "\"$IDENTITY\""
}

if has_valid_identity; then
  echo "Identity \"$IDENTITY\" already exists and is valid."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate already in the keychain but not trusted; adding trust only."
  security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$WORK/cert.pem"
else
  echo "Creating self-signed code signing certificate \"$IDENTITY\" ($DAYS days)…"
  cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days "$DAYS" \
    -config "$WORK/openssl.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

  # macOS `security import` only understands legacy PKCS#12 encryption (3DES/SHA1),
  # not the AES/PBKDF2 default of OpenSSL 3+.
  # (Not `tr < /dev/urandom | head`: tr dies of SIGPIPE, which pipefail turns into a silent exit.)
  PASS="$("$OPENSSL" rand -hex 16)"
  "$OPENSSL" pkcs12 -export -name "$IDENTITY" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/identity.p12" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$PASS"

  echo "Importing into the login keychain…"
  security import "$WORK/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
fi

echo "Trusting the certificate for code signing (macOS will ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if has_valid_identity; then
  echo "Done. Identity:"
  security find-identity -v -p codesigning "$KEYCHAIN" | grep -F "\"$IDENTITY\""
  echo "On the first build, choose \"Always Allow\" when codesign asks to use the key."
else
  echo "error: identity \"$IDENTITY\" is still not valid for code signing." >&2
  exit 1
fi
