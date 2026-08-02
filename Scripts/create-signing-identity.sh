#!/usr/bin/env bash
#
# Creates a self-signed code-signing identity named "Mavica Copy Signing" in
# the login keychain, so build-app.sh can produce a stable (non-ad-hoc)
# signature without an Apple Developer certificate or Xcode.
#
# Run this INTERACTIVELY: macOS will show one or two security dialogs
# (trust-settings change, and the first time codesign uses the new key).
#
# Usage: Scripts/create-signing-identity.sh

set -euo pipefail

identity_name="Mavica Copy Signing"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$identity_name"; then
  echo "Identity \"$identity_name\" already exists and is valid. Nothing to do."
  exit 0
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> Generating self-signed code-signing certificate (10-year validity)"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$workdir/key.pem" \
  -out "$workdir/cert.pem" \
  -subj "/CN=${identity_name}" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false"

echo "==> Packaging identity"
openssl pkcs12 -export \
  -inkey "$workdir/key.pem" \
  -in "$workdir/cert.pem" \
  -out "$workdir/identity.p12" \
  -passout pass:mavica-temp

echo "==> Importing into login keychain"
security import "$workdir/identity.p12" \
  -k "${HOME}/Library/Keychains/login.keychain-db" \
  -P mavica-temp \
  -T /usr/bin/codesign

echo "==> Trusting the certificate for code signing (this may show a password dialog)"
security add-trusted-cert -p codeSign \
  -k "${HOME}/Library/Keychains/login.keychain-db" \
  "$workdir/cert.pem"

echo ""
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$identity_name"; then
  echo "Done. \"$identity_name\" is ready — rebuild with Scripts/build-app.sh."
  echo "The first build may show one 'codesign wants to sign' dialog: click Always Allow."
else
  echo "The identity was imported but is not yet reported as valid."
  echo "Open Keychain Access, find \"$identity_name\", and set Trust > Code Signing to Always Trust,"
  echo "then rebuild with Scripts/build-app.sh."
fi
