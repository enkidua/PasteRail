#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP="$ROOT/.build/universal/PasteRail.app"
ARCHIVE="$ROOT/PasteRail-$VERSION-universal.zip"

"$ROOT/Scripts/build-universal.sh"
codesign --verify --deep --strict --verbose=2 "$APP"
lipo -info "$APP/Contents/MacOS/PasteRail"

rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo "$ARCHIVE"
