#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP="$ROOT/.build/universal/PasteRail.app"
DMG="$ROOT/PasteRail-$VERSION-universal.dmg"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-test-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

rm -f "$DMG"
"$ROOT/Scripts/build-universal.sh"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "io.pasterail.PasteRail"
lipo "$APP/Contents/MacOS/PasteRail" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$APP"

ditto --norsrc --noextattr "$APP" "$STAGING/PasteRail.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "PasteRail $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

echo "Created local manual-test DMG: $DMG"
echo "Signature: ad-hoc manual-test build."
echo "Notarization: not Developer ID signed and not Apple notarized."
echo "Keychain: the default build uses a local key file, so no Keychain prompt should appear."
echo "Gatekeeper: warnings may still appear until a Developer ID notarized release exists."
