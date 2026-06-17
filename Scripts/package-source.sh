#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
ARCHIVE="$ROOT/PasteRail-$VERSION-source.zip"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-source.XXXXXX")"
PACKAGE="$STAGING/PasteRail-$VERSION"
FORBIDDEN_PATTERN='(^|/)(\.build|\.swiftpm|DerivedData|ModuleCache|[^/]*\.dSYM|[^/]*\.dSYM/|__MACOSX|PasteRail\.app|[^/]*\.app/|PasteRail-[^/]*-universal\.zip|[^/]*\.log|\.DS_Store|xcuserdata|[^/]*\.xcuserstate)(/|$)'

cleanup() {
  rm -rf "$STAGING"
}
trap cleanup EXIT

mkdir -p "$PACKAGE"
cp "$ROOT/Package.swift" "$PACKAGE/"
cp -R "$ROOT/PasteRail" "$PACKAGE/"
cp -R "$ROOT/Scripts" "$PACKAGE/"
cp "$ROOT/README.md" "$PACKAGE/"
cp "$ROOT/DEVELOPMENT.md" "$PACKAGE/"
cp "$ROOT/MANUAL_TEST.md" "$PACKAGE/"
cp "$ROOT/PRIVACY.md" "$PACKAGE/"
cp "$ROOT/LICENSE" "$PACKAGE/"
cp -R "$ROOT/.github" "$PACKAGE/"
cp "$ROOT/.gitignore" "$PACKAGE/"

find "$PACKAGE" \( \
  -name .build -o \
  -name .swiftpm -o \
  -name DerivedData -o \
  -name ModuleCache -o \
  -name '*.dSYM' -o \
  -name '*.dSYM.zip' -o \
  -name '*.app' -o \
  -name 'PasteRail-*.zip' -o \
  -name '*.log' -o \
  -name .DS_Store -o \
  -name xcuserdata -o \
  -name '*.xcuserstate' \
\) -prune -exec rm -rf {} +

rm -f "$ARCHIVE"
(
  cd "$STAGING"
  /usr/bin/zip -qry "$ARCHIVE" "PasteRail-$VERSION"
)
if unzip -l "$ARCHIVE" | grep -E "$FORBIDDEN_PATTERN"; then
  echo "Forbidden build or user artifact found in $ARCHIVE" >&2
  exit 1
fi
echo "$ARCHIVE"
