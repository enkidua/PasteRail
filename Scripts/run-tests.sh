#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_CACHE="$(mktemp -d "${TMPDIR:-/tmp}/PasteRail-xctest-check.XXXXXX")"
cleanup() {
  rm -rf "$CHECK_CACHE"
}
trap cleanup EXIT

if ! swift -Xcc "-fmodules-cache-path=$CHECK_CACHE" -e 'import XCTest; print("XCTest OK")' >"$CHECK_CACHE/output.log" 2>&1; then
  cat >&2 <<'EOF'
XCTest is not available in this Swift toolchain.

PasteRail's ordinary test suite currently uses XCTest and is expected to run in
GitHub Actions or a full Xcode environment. Command Line Tools for the macOS 15
SDK can still build the app and create the manual-test DMG, but cannot execute
these XCTest targets. With Command Line Tools for the macOS 27 SDK, also set
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk for app builds,
because SwiftUI's macros there need Xcode's plugin.

Use these commands for local build/package verification:

  rm -rf .build .swiftpm
  swift build -c release
  ./Scripts/build-universal.sh
  ./Scripts/package-dmg.sh

EOF
  cat "$CHECK_CACHE/output.log" >&2
  exit 1
fi

swift test --package-path "$ROOT" --filter PasteRailTests

if [ "${PASTERAIL_RUN_KEYCHAIN_TESTS:-0}" = "1" ]; then
  swift test --package-path "$ROOT" --filter KeychainIntegrationTests
else
  echo "Skipping Keychain integration tests. Set PASTERAIL_RUN_KEYCHAIN_TESTS=1 to run them."
fi
