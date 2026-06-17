#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUNDLE_ID="io.pasterail.PasteRail"
APP="$ROOT/.build/universal/PasteRail.app"
DMG="$ROOT/PasteRail-$VERSION-release.dmg"
APP_ZIP="$ROOT/.build/PasteRail-$VERSION-notary.zip"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-release-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING"
  rm -f "$APP_ZIP"
}
trap cleanup EXIT

IDENTITIES="$(security find-identity -v -p codesigning 2>&1 || true)"
if [ -z "${DEVELOPER_ID_APPLICATION:-}" ] || \
   ! grep -Fq "$DEVELOPER_ID_APPLICATION" <<<"$IDENTITIES"; then
  echo "A matching DEVELOPER_ID_APPLICATION certificate is unavailable." >&2
  echo "Creating an ad-hoc manual-test DMG instead; release signing did not succeed." >&2
  "$ROOT/Scripts/package-test-dmg.sh" "$VERSION"
  exit 2
fi
: "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to the Developer ID certificate team identifier}"

rm -f "$DMG" "$APP_ZIP"
"$ROOT/Scripts/build-universal.sh"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$BUNDLE_ID"
lipo "$APP/Contents/MacOS/PasteRail" -verify_arch arm64 x86_64

codesign --force --deep --strict \
  --sign "$DEVELOPER_ID_APPLICATION" \
  --identifier "$BUNDLE_ID" \
  --options runtime \
  --timestamp \
  "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

SIGN_DETAILS="$(codesign -dv --verbose=4 "$APP" 2>&1)"
SIGNED_TEAM="$(awk -F= '/^TeamIdentifier=/{print $2; exit}' <<<"$SIGN_DETAILS")"
SIGNED_ID="$(awk -F= '/^Identifier=/{print $2; exit}' <<<"$SIGN_DETAILS")"
test "$SIGNED_TEAM" = "$DEVELOPMENT_TEAM"
test "$SIGNED_ID" = "$BUNDLE_ID"
grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$SIGN_DETAILS"
grep -Eq '^Timestamp=' <<<"$SIGN_DETAILS"

COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$APP" "$APP_ZIP"
"$ROOT/Scripts/notarize-release.sh" "$APP_ZIP" "$APP"
spctl --assess --type execute --verbose=4 "$APP"

ditto --norsrc --noextattr "$APP" "$STAGING/PasteRail.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "PasteRail $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG"
codesign --verify --deep --strict --verbose=2 "$DMG"
"$ROOT/Scripts/notarize-release.sh" "$DMG"
codesign --verify --deep --strict --verbose=2 "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"

echo "Developer ID signed and notarized release DMG: $DMG"
