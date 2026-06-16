#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
SOURCE_ZIP="$ROOT/PasteRail-$VERSION-source.zip"
APP_ZIP="$ROOT/PasteRail-$VERSION-universal.zip"
ARCHIVE="$ROOT/PasteRail-$VERSION-review.zip"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-review.XXXXXX")"
PACKAGE="$STAGING/PasteRail-$VERSION-review"
FORBIDDEN_PATTERN='(^|/)(\.build|\.swiftpm|DerivedData|ModuleCache|[^/]*\.dSYM|[^/]*\.dSYM/|__MACOSX|PasteRail\.app|[^/]*\.app/|[^/]*\.log|\.DS_Store|xcuserdata|[^/]*\.xcuserstate)(/|$)'

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

if [ ! -f "$SOURCE_ZIP" ]; then
  "$ROOT/Scripts/package-source.sh" "$VERSION" >/dev/null
fi

if [ ! -f "$APP_ZIP" ]; then
  "$ROOT/Scripts/package-universal.sh" "$VERSION" >/dev/null
fi

mkdir -p "$PACKAGE"
cp "$SOURCE_ZIP" "$PACKAGE/"
cp "$APP_ZIP" "$PACKAGE/"
cp "$ROOT/README.md" "$PACKAGE/"
cp "$ROOT/DEVELOPMENT.md" "$PACKAGE/"
if [ -f "$ROOT/PRIVACY.md" ]; then
  cp "$ROOT/PRIVACY.md" "$PACKAGE/"
fi

rm -f "$ARCHIVE"
(
  cd "$STAGING"
  /usr/bin/zip -qry "$ARCHIVE" "PasteRail-$VERSION-review"
)

if unzip -l "$ARCHIVE" | grep -E "$FORBIDDEN_PATTERN"; then
  echo "Forbidden build or user artifact found in $ARCHIVE" >&2
  exit 1
fi

echo "$ARCHIVE"
