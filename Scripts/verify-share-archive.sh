#!/bin/zsh
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <archive.zip>" >&2
  exit 64
fi

ARCHIVE="$1"

if [ ! -f "$ARCHIVE" ]; then
  echo "Archive not found: $ARCHIVE" >&2
  exit 66
fi

FORBIDDEN_PATTERN='(^|/)(\.build|\.swiftpm|DerivedData|ModuleCache|[^/]*\.dSYM|[^/]*\.dSYM/|PasteRail\.app|[^/]*\.app/|\.DS_Store|\._[^/]*|[^/]*\.log|__MACOSX)(/|$)'

MATCHES="$(unzip -l "$ARCHIVE" | awk 'NF >= 4 { print $4 }' | grep -E "$FORBIDDEN_PATTERN" || true)"

if [ -n "$MATCHES" ]; then
  MATCH_COUNT="$(printf '%s\n' "$MATCHES" | wc -l | tr -d '[:space:]')"
  echo "Forbidden build, cache, app, log, or user artifact found in $ARCHIVE:" >&2
  echo "Forbidden item count: $MATCH_COUNT" >&2
  echo "Showing first 50 forbidden entries:" >&2
  printf '%s\n' "$MATCHES" | awk 'NR <= 50 { print }' >&2
  echo "Do not upload project-root ZIP files. Upload PasteRail-0.1.0-review.zip only." >&2
  exit 1
fi

echo "Share archive verified: $ARCHIVE"
