#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP="$ROOT/.build/universal/PasteRail.app"
DMG="$ROOT/PasteRail-$VERSION-universal.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

rm -f "$DMG"
"$ROOT/Scripts/build-universal.sh"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/PasteRail" -verify_arch arm64 x86_64

cp -R "$APP" "$STAGING/PasteRail.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "PasteRail $VERSION" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$DMG"
hdiutil verify "$DMG"

echo "Local manual-test DMG (ad-hoc signed, not notarized): $DMG"
