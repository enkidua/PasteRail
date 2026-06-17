#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP="$ROOT/.build/universal/PasteRail.app"
ARCHIVE="$ROOT/PasteRail-$VERSION-universal.zip"
MODE="${2:-}"

if [ "$MODE" = "--reuse-build" ]; then
  if [ ! -x "$APP/Contents/MacOS/PasteRail" ]; then
    echo "Reusable Universal app not found: $APP" >&2
    exit 1
  fi
elif [ -n "$MODE" ]; then
  echo "Usage: $0 [version] [--reuse-build]" >&2
  exit 64
else
  "$ROOT/Scripts/build-universal.sh"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
lipo "$APP/Contents/MacOS/PasteRail" -verify_arch arm64 x86_64
lipo -info "$APP/Contents/MacOS/PasteRail"

rm -f "$ARCHIVE"
COPYFILE_DISABLE=1 ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ARCHIVE"
"$ROOT/Scripts/verify-universal-archive.sh" "$ARCHIVE"
echo "$ARCHIVE"
