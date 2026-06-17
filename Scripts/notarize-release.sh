#!/bin/zsh
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 <submission.zip-or.dmg> [staple-target]" >&2
  exit 64
fi

SUBMISSION="$1"
STAPLE_TARGET="${2:-$SUBMISSION}"

if [ ! -f "$SUBMISSION" ]; then
  echo "Notarization submission not found: $SUBMISSION" >&2
  exit 66
fi
if [ ! -e "$STAPLE_TARGET" ]; then
  echo "Staple target not found: $STAPLE_TARGET" >&2
  exit 66
fi

if [ -n "${NOTARYTOOL_PROFILE:-}" ]; then
  AUTH_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
else
  : "${APPLE_ID:?Set APPLE_ID or NOTARYTOOL_PROFILE}"
  : "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD or NOTARYTOOL_PROFILE}"
  : "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM or NOTARYTOOL_PROFILE}"
  AUTH_ARGS=(--apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$DEVELOPMENT_TEAM")
fi

xcrun notarytool submit "$SUBMISSION" "${AUTH_ARGS[@]}" --wait
xcrun stapler staple "$STAPLE_TARGET"
xcrun stapler validate "$STAPLE_TARGET"
