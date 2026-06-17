#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
SOURCE_ZIP="$ROOT/PasteRail-$VERSION-source.zip"
APP_ZIP="$ROOT/PasteRail-$VERSION-universal.zip"
ARCHIVE="$ROOT/PasteRail-$VERSION-review.zip"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-review.XXXXXX")"
PACKAGE="$STAGING/PasteRail-$VERSION-review"

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

ensure_current() {
  local archive="$1"
  shift
  local newer
  newer="$(find "$@" -type f -newer "$archive" -print -quit)"
  if [ -n "$newer" ]; then
    echo "Generated archive is older than current source: $newer" >&2
    exit 1
  fi
}

# Never leave an older review archive available after a failed rebuild.
rm -f "$ARCHIVE"

"$ROOT/Scripts/package-source.sh" "$VERSION"
ensure_current "$SOURCE_ZIP" \
  "$ROOT/Package.swift" "$ROOT/PasteRail" "$ROOT/Scripts" \
  "$ROOT/README.md" "$ROOT/DEVELOPMENT.md" "$ROOT/PRIVACY.md" \
  "$ROOT/RELEASE.md" "$ROOT/MANUAL_TEST.md" "$ROOT/LICENSE" "$ROOT/.github" "$ROOT/.gitignore"

"$ROOT/Scripts/package-universal.sh" "$VERSION"
ensure_current "$APP_ZIP" \
  "$ROOT/Package.swift" "$ROOT/PasteRail/Sources" "$ROOT/PasteRail/Resources" \
  "$ROOT/Scripts/build-universal.sh" "$ROOT/Scripts/package-universal.sh"

"$ROOT/Scripts/verify-universal-archive.sh" "$APP_ZIP"

mkdir -p "$PACKAGE"
cp "$SOURCE_ZIP" "$PACKAGE/"
cp "$APP_ZIP" "$PACKAGE/"
cp "$ROOT/README.md" "$PACKAGE/"
cp "$ROOT/DEVELOPMENT.md" "$PACKAGE/"
cp "$ROOT/RELEASE.md" "$PACKAGE/"
cp "$ROOT/MANUAL_TEST.md" "$PACKAGE/"
if [ -f "$ROOT/PRIVACY.md" ]; then
  cp "$ROOT/PRIVACY.md" "$PACKAGE/"
fi

(
  cd "$STAGING"
  /usr/bin/zip -qry "$ARCHIVE" "PasteRail-$VERSION-review"
)

"$ROOT/Scripts/verify-share-archive.sh" "$ARCHIVE"

echo "Upload this file only: $ARCHIVE"
