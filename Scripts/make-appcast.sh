#!/bin/bash
# Emits build/site/appcast.xml (plus an index stub) for the given release dmg.
# Env: VERSION (required), BUILD, DMG (default build/CODENAME-$VERSION.dmg),
#      SPARKLE_ED_PRIVATE_KEY_FILE (required: EdDSA private key exported by generate_keys),
#      DOWNLOAD_URL_BASE (default GitHub release download path for vVERSION).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:?set VERSION}"
BUILD="${BUILD:-1}"
DMG="${DMG:-build/CODENAME-$VERSION.dmg}"
KEY_FILE="${SPARKLE_ED_PRIVATE_KEY_FILE:?set SPARKLE_ED_PRIVATE_KEY_FILE}"
URL_BASE="${DOWNLOAD_URL_BASE:-https://github.com/Lonkins/CODENAME/releases/download/v$VERSION}"
SIGN_UPDATE="Packages/CODENAMEKit/.build/artifacts/sparkle/Sparkle/bin/sign_update"

[ -f "$DMG" ] || { echo "error: $DMG not found" >&2; exit 1; }
[ -x "$SIGN_UPDATE" ] || { echo "error: sign_update missing — run swift build first" >&2; exit 1; }

# sign_update prints: sparkle:edSignature="..." length="..."
SIG_ATTRS="$("$SIGN_UPDATE" --ed-key-file "$KEY_FILE" "$DMG")"

mkdir -p build/site
cat > build/site/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>CODENAME</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>$(date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <enclosure url="$URL_BASE/$(basename "$DMG")" $SIG_ATTRS type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML

cat > build/site/index.html <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>CODENAME</title>
<p>CODENAME update feed. Releases: <a href="https://github.com/Lonkins/CODENAME/releases">GitHub</a>.</p>
HTML

xmllint --noout build/site/appcast.xml
grep -q 'sparkle:edSignature=' build/site/appcast.xml || { echo "error: appcast missing edSignature" >&2; exit 1; }
echo "appcast: build/site/appcast.xml"
