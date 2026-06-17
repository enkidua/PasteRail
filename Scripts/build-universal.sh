#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/universal"
APP="$BUILD/PasteRail.app"

rm -rf "$BUILD"
mkdir -p "$BUILD/arm64" "$BUILD/x86_64" "$APP/Contents/MacOS" "$APP/Contents/Resources"

swift build -c release --package-path "$ROOT" --scratch-path "$BUILD/arm64" --triple arm64-apple-macosx13.0
swift build -c release --package-path "$ROOT" --scratch-path "$BUILD/x86_64" --triple x86_64-apple-macosx13.0

lipo -create \
  "$BUILD/arm64/arm64-apple-macosx/release/PasteRail" \
  "$BUILD/x86_64/x86_64-apple-macosx/release/PasteRail" \
  -output "$APP/Contents/MacOS/PasteRail"

cp "$ROOT/PasteRail/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/PasteRail/Resources/PasteRail.icns" "$APP/Contents/Resources/PasteRail.icns"
codesign --force --deep --sign - "$APP"
lipo "$APP/Contents/MacOS/PasteRail" -verify_arch arm64 x86_64
lipo -info "$APP/Contents/MacOS/PasteRail"
echo "$APP"
