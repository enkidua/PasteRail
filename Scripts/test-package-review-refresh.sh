#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
SOURCE_ZIP="$ROOT/PasteRail-$VERSION-source.zip"
APP_ZIP="$ROOT/PasteRail-$VERSION-universal.zip"
REVIEW_ZIP="$ROOT/PasteRail-$VERSION-review.zip"

printf 'stale source archive\n' > "$SOURCE_ZIP"
printf 'stale app archive\n' > "$APP_ZIP"
printf 'stale review archive\n' > "$REVIEW_ZIP"

"$ROOT/Scripts/package-review.sh" "$VERSION"

unzip -tq "$SOURCE_ZIP" >/dev/null
unzip -tq "$APP_ZIP" >/dev/null
unzip -tq "$REVIEW_ZIP" >/dev/null
unzip -Z1 "$SOURCE_ZIP" | awk -v expected="PasteRail-$VERSION/Package.swift" '$0 == expected { found = 1 } END { exit !found }'
unzip -Z1 "$SOURCE_ZIP" | awk -v expected="PasteRail-$VERSION/PasteRail/Sources/ClipStore.swift" '$0 == expected { found = 1 } END { exit !found }'
unzip -Z1 "$SOURCE_ZIP" | awk -v expected="PasteRail-$VERSION/MANUAL_TEST.md" '$0 == expected { found = 1 } END { exit !found }'
"$ROOT/Scripts/verify-universal-archive.sh" "$APP_ZIP"
unzip -Z1 "$REVIEW_ZIP" | awk -v expected="PasteRail-$VERSION-review/PasteRail-$VERSION-source.zip" '$0 == expected { found = 1 } END { exit !found }'
unzip -Z1 "$REVIEW_ZIP" | awk -v expected="PasteRail-$VERSION-review/PasteRail-$VERSION-universal.zip" '$0 == expected { found = 1 } END { exit !found }'
unzip -Z1 "$REVIEW_ZIP" | awk -v expected="PasteRail-$VERSION-review/MANUAL_TEST.md" '$0 == expected { found = 1 } END { exit !found }'
"$ROOT/Scripts/verify-share-archive.sh" "$REVIEW_ZIP"

echo "Packaging refresh verified: existing archives were not reused."
