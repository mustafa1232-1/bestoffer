#!/usr/bin/env bash
set -euo pipefail

OUT_FILE="${1:-keys/maslaki-upload.jks}"
ALIAS="${2:-upload}"
VALIDITY_DAYS="${3:-10000}"
KEYALG="RSA"
KEYSIZE="2048"

mkdir -p "$(dirname "$OUT_FILE")"

echo "Generating keystore: $OUT_FILE"
echo "Alias: $ALIAS"

echo "You will be prompted for passwords by keytool."
keytool -genkeypair \
  -v \
  -keystore "$OUT_FILE" \
  -alias "$ALIAS" \
  -keyalg "$KEYALG" \
  -keysize "$KEYSIZE" \
  -validity "$VALIDITY_DAYS"

echo
echo "Done. Next steps:"
echo "1) Copy android/key.properties.example to android/key.properties"
echo "2) Fill storePassword/keyPassword/keyAlias/storeFile"