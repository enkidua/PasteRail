#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/universal"
APP="$BUILD/PasteRail.app"

rm -rf "$BUILD"
mkdir -p "$BUILD/arm64" "$BUILD/x86_64" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Ask SwiftPM for each output directory: older SwiftPM writes to
# <triple>/release, while the newer build system writes to out/Products/Release.
binaries=()
for arch in arm64 x86_64; do
  args=(-c release --package-path "$ROOT" --scratch-path "$BUILD/$arch" --triple "$arch-apple-macosx13.0")
  swift build "${args[@]}"
  binaries+=("$(swift build "${args[@]}" --show-bin-path)/PasteRail")
done

lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/PasteRail"

cp "$ROOT/PasteRail/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/PasteRail/Resources/PasteRail.icns" "$APP/Contents/Resources/PasteRail.icns"
codesign --force --deep --sign - "$APP"
for arch in arm64 x86_64; do lipo "$APP/Contents/MacOS/PasteRail" -verify_arch "$arch"; done
lipo -info "$APP/Contents/MacOS/PasteRail"
echo "$APP"
