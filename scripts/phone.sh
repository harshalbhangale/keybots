#!/bin/sh
# Builds Keybots for the connected iPhone against the hosted server and installs it.
# The API token is read from keys/api-token (gitignored) and never printed.
#   KEYS=/path/to/keys DEVICE=<udid> TEAM=<team id> sh scripts/phone.sh
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KEYS=${KEYS:-$ROOT/keys}
DEVICE=${DEVICE:-00008140-000C752C3CC3801C}
TEAM=${TEAM:-R3D54PSMD2}
SERVER=${AIRKEY_SERVER:-https://13-126-207-245.sslip.io}
OUT=${TMPDIR:-/tmp}/keybots-phone
[ -s "$KEYS/api-token" ] || { echo "No API token at $KEYS/api-token"; exit 1; }
TOKEN=$(cat "$KEYS/api-token")
cd "$ROOT/ios"
xcodebuild -project AirKey.xcodeproj -scheme AirKey -destination "id=$DEVICE" -derivedDataPath "$OUT" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_ENTITLEMENTS= \
  AIRKEY_SERVER="$SERVER" AIRKEY_TOKEN="$TOKEN" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun devicectl device install app --device "$DEVICE" "$OUT/Build/Products/Debug-iphoneos/AirKey.app" 2>&1 | grep -iE "installed|error"
echo "Server: $SERVER"
