#!/bin/zsh
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <universal-app.zip>" >&2
  exit 64
fi

ARCHIVE="$1"
if [ ! -f "$ARCHIVE" ]; then
  echo "Archive not found: $ARCHIVE" >&2
  exit 66
fi

unzip -tq "$ARCHIVE" >/dev/null
ENTRIES="$(unzip -Z1 "$ARCHIVE")"
FORBIDDEN='(^|/)(__MACOSX|\.build|\.swiftpm|DerivedData|ModuleCache|[^/]*\.dSYM|\.DS_Store|\._[^/]*|[^/]*\.log)(/|$)'

if printf '%s\n' "$ENTRIES" | grep -E "$FORBIDDEN"; then
  echo "Forbidden artifact found in Universal application archive: $ARCHIVE" >&2
  exit 1
fi
if printf '%s\n' "$ENTRIES" | grep -Ev '^PasteRail\.app(/|$)'; then
  echo "Universal ZIP must contain PasteRail.app only: $ARCHIVE" >&2
  exit 1
fi
printf '%s\n' "$ENTRIES" | grep -qx 'PasteRail.app/Contents/Info.plist'
printf '%s\n' "$ENTRIES" | grep -qx 'PasteRail.app/Contents/MacOS/PasteRail'

echo "Universal application archive verified: $ARCHIVE"
