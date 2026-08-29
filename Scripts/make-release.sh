#!/bin/bash
# Builds the distributable: signed, notarized, stapled CODENAME-<version>.dmg.
# Without CODESIGN_IDENTITY this is a DRY RUN: ad-hoc signed dmg, no notarization.
# Env: VERSION (required), BUILD, CODESIGN_IDENTITY ("Developer ID Application: ..."),
#      ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID (App Store Connect API key, signing runs only).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:?set VERSION, e.g. 0.0.1}"
BUILD="${BUILD:-1}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/CODENAME.app"
DMG="build/CODENAME-$VERSION.dmg"

notarize() {
  xcrun notarytool submit "$1" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
    --wait --timeout 30m
}

VERSION="$VERSION" BUILD="$BUILD" CONFIG=release CODESIGN_IDENTITY="$IDENTITY" ./Scripts/make-app.sh

if [ "$IDENTITY" != "-" ]; then
  : "${ASC_KEY_PATH:?}" "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}"
  ditto -c -k --keepParent "$APP" build/CODENAME-app.zip
  notarize build/CODENAME-app.zip
  xcrun stapler staple "$APP"
else
  echo "DRY RUN: ad-hoc identity, skipping app notarization and stapling" >&2
fi

rm -f "$DMG"
hdiutil create -volname "CODENAME" -srcfolder "$APP" -ov -format UDZO "$DMG"

if [ "$IDENTITY" != "-" ]; then
  codesign --force --sign "$IDENTITY" "$DMG"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
else
  echo "DRY RUN: dmg is ad-hoc signed and will NOT pass Gatekeeper" >&2
fi

shasum -a 256 "$DMG" > "$DMG.sha256"
cat "$DMG.sha256"
echo "release artifact: $DMG"
