#!/bin/bash
# Assembles and signs CODENAME.app from the SwiftPM build (see docs/adr/0002-project-format.md).
# Env: VERSION (default 0.0.1), BUILD (default 1), CONFIG (debug|release),
#      CODESIGN_IDENTITY (default "-" = ad-hoc; release CI passes a Developer ID).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.1}"
BUILD="${BUILD:-1}"
CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/CODENAME.app"

swift build --package-path Packages/CODENAMEKit -c "$CONFIG" --product CODENAMEApp
BIN="$(swift build --package-path Packages/CODENAMEKit -c "$CONFIG" --show-bin-path)/CODENAMEApp"

file "$BIN" | grep -q "arm64" || { echo "error: binary is not arm64" >&2; exit 1; }
file "$BIN" | grep -qv "universal" || { echo "error: universal binary produced" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CODENAME"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" App/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --options runtime \
  --entitlements App/CODENAME.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --verbose=2 "$APP"

echo "built: $APP (v$VERSION build $BUILD, $CONFIG, identity: $IDENTITY)"
