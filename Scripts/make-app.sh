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
swift build --package-path Packages/CODENAMEKit -c "$CONFIG" --product TestCore
swift build --package-path Packages/CODENAMEKit -c "$CONFIG" --product CoreHostXPC
BUILD_DIR="$(swift build --package-path Packages/CODENAMEKit -c "$CONFIG" --show-bin-path)"
BIN="$BUILD_DIR/CODENAMEApp"

file "$BIN" | grep -q "arm64" || { echo "error: binary is not arm64" >&2; exit 1; }
file "$BIN" | grep -qv "universal" || { echo "error: universal binary produced" >&2; exit 1; }

SPARKLE_FRAMEWORK="Packages/CODENAMEKit/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "error: Sparkle.framework artifact missing" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" \
  "$APP/Contents/Resources"
# Licence texts for bundled cores (distributor obligation, ADR 0001).
cp -R App/CoreLicences "$APP/Contents/Resources/"
cp "$BIN" "$APP/Contents/MacOS/CODENAME"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/"
# Development core until curated cores land (ADR 0001).
cp "$BUILD_DIR/libTestCore.dylib" "$APP/Contents/PlugIns/"
# Real cores ride along when built (Scripts/build-cores.sh).
if ls build/cores/*.dylib >/dev/null 2>&1; then
  cp build/cores/*.dylib "$APP/Contents/PlugIns/"
fi
# Helper-only cores (GPL, ADR 0007) go in a subdirectory the app-process
# trust policy refuses by construction; only the helper may load them.
if ls build/cores/helper-only/*.dylib >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/PlugIns/HelperOnly"
  cp build/cores/helper-only/*.dylib "$APP/Contents/PlugIns/HelperOnly/"
  # Sidecars are data, not code: inside PlugIns they would break the code
  # seal (codesign treats PlugIns entries as code objects).
  mkdir -p "$APP/Contents/Resources/HelperOnly"
  cp build/cores/helper-only/*.info "$APP/Contents/Resources/HelperOnly/" 2>/dev/null || true
fi

# Bundled XPC core-host service (ADR 0006 step B).
XPC_BUNDLE="$APP/Contents/XPCServices/CoreHost.xpc"
mkdir -p "$XPC_BUNDLE/Contents/MacOS"
cp "$BUILD_DIR/CoreHostXPC" "$XPC_BUNDLE/Contents/MacOS/CoreHost"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" App/CoreHost-Info.plist \
  > "$XPC_BUNDLE/Contents/Info.plist"
lipo -thin arm64 "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle" \
  -output "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" App/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Hardened runtime only with a real identity: library validation requires a
# shared Team ID, which ad-hoc signatures don't have (see ADR 0001).
# Plain string, expanded unquoted: empty arrays trip `set -u` on bash 3.2.
RUNTIME_OPTS=""
if [ "$IDENTITY" != "-" ]; then RUNTIME_OPTS="--options runtime"; fi

# Sign inside-out: plug-ins and Sparkle's nested services, the framework, then the app.
for plugin in "$APP/Contents/PlugIns/"*.dylib "$APP/Contents/PlugIns/HelperOnly/"*.dylib; do
  [ -e "$plugin" ] || continue  # unmatched glob under set -u
  codesign --force $RUNTIME_OPTS --sign "$IDENTITY" "$plugin"
done
codesign --force $RUNTIME_OPTS --sign "$IDENTITY" "$XPC_BUNDLE"
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for NESTED in \
  "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
  "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
  "$FRAMEWORK/Versions/B/Autoupdate" \
  "$FRAMEWORK/Versions/B/Updater.app"; do
  [ -e "$NESTED" ] && codesign --force $RUNTIME_OPTS --preserve-metadata=entitlements \
    --sign "$IDENTITY" "$NESTED"
done
codesign --force $RUNTIME_OPTS --sign "$IDENTITY" "$FRAMEWORK"
codesign --force $RUNTIME_OPTS \
  --entitlements App/CODENAME.entitlements \
  --sign "$IDENTITY" "$APP"
codesign --verify --deep --verbose=2 "$APP"

echo "built: $APP (v$VERSION build $BUILD, $CONFIG, identity: $IDENTITY)"
