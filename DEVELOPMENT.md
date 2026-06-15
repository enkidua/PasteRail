# PasteRail Development Record

## Product status

Status: **MVP stabilization in progress**.

The MVP remains incomplete until tests, real application paste behavior, and a
Universal 2 Release build pass on supported Intel and Apple Silicon Macs. OCR and
advanced features are not in progress.

## Source separation

The initial repository contained an upstream clipboard-manager reference tree.
PasteRail was implemented as an independent Swift package with new types, storage
formats, UI, bundle identifier, settings names, and resources. No upstream source
file is imported by `Package.swift`, and no source block was copied into the
PasteRail target. A repository-wide dependency and identifier search was performed
before removing the reference tree. Therefore no third-party source notice is
required for the current target beyond the PasteRail MIT license.

## Architecture

- SwiftUI panel hosted in an AppKit `NSPanel`
- AppKit pasteboard monitoring with item boundaries preserved
- App-only local storage under `io.pasterail.PasteRail`
- Atomic JSON index, previous-index backup, corrupt-index preservation, separate
  payload/image/thumbnail files, private POSIX permissions, and guarded orphan cleanup
- AES-256-GCM encryption for the index, payloads, original images, and thumbnails;
  the 256-bit key is stored in the macOS Keychain
- No network libraries or remote services

## Paste success definition

A queue operation advances only when all three observable steps succeed:

1. The target application is activated.
2. The clipboard payload is written.
3. The Command-V keyboard events are created and posted.

macOS does not provide a common API that proves the target application consumed
or inserted the data. PasteRail does not claim that final insertion is guaranteed.

`NSPasteboard` does not provide a transactional replacement API. PasteRail snapshots
the previous item representations before clearing the pasteboard and attempts to
restore them if the new write fails. Restoration can also fail if the pasteboard
server rejects the second write.

The snapshot remains available until Command-V event posting succeeds. Event
failure triggers restoration, and the result distinguishes restoration success
from restoration failure. Queue progress advances only for the event-sent result.
Successful event posting immediately discards the in-memory previous-clipboard
snapshot. Restoration paths also discard it regardless of restoration success, and
each new paste begins by discarding any stale snapshot from an interrupted operation.
Clipboard snapshots are never written to disk or logged.

## Recovery safety

Automatic orphan deletion is disabled in every startup path. Payloads and images
remain in their original directories and potential orphans are listed with path,
size, discovery time, type, and a minimum seven-day grace date in
`Recovery/orphan-candidates.json`. No recovery candidate is deleted until a future
explicit user cleanup operation exists.

## Clipboard source accuracy

On application activation, PasteRail checks the pasteboard change counter before
replacing the source candidate. A pending change is attributed to the previous
application. Missing or ambiguous source state fails closed. Background agents,
scripts, and remote clipboard features can still lack a reliable source and are
therefore not recorded.

## Encryption migration

Legacy plaintext files are encrypted to new files without overwriting the originals.
A path-only cleanup marker is written before the encrypted index commit, but cleanup
is permitted only after that encrypted index exists and authenticates successfully.
Migration failure leaves the original plaintext intact.

The cleanup marker is itself AES-GCM encrypted and contains only storage-relative
path pairs. Cleanup rejects absolute paths, parent traversal, symbolic links,
non-approved directories, unauthenticated encrypted files, and files not referenced
by the authenticated encrypted index.

Cleanup performs two complete validation passes. The second pass, immediately before
removal, repeats path containment, symlink, encrypted-file authentication, and index
reference checks and compares the plaintext file device/inode identity captured by
the first pass. All entries must pass before cleanup proceeds. PasteRail then writes
an AES-GCM recovery copy with a random `.enc` filename under
`Recovery/PlaintextQuarantine`, reopens and authenticates that copy, and compares its
decrypted bytes with the source. Only then is the legacy plaintext file removed.
The encrypted cleanup marker remains when cleanup fails so startup can retry.

Logical deletion cannot guarantee physical secure erasure on APFS, SSD wear
leveling, snapshots, or backups. Release documentation recommends FileVault for
at-rest protection.

Index persistence creates and validates a temporary backup copy before atomically
renaming it over `history.backup.enc`. Temporary-copy or replacement failure leaves
the existing backup untouched. Both bootstrap migration writes and ordinary store
writes use the same backup routine.

`ClipStore` bootstrap is static and receives the locally created `CryptoStore` and
storage URLs as arguments. Initial index decryption and snapshot construction finish
before any stored property is assigned, so initialization does not call an instance
method on a partially initialized actor.

Encrypted-index decode failures and plaintext-cleanup failures are handled
independently. A cleanup warning never replaces a valid current snapshot with the
backup snapshot. The authenticated cleanup plan remains available for a later retry,
and corrupt encrypted indexes are preserved with an `.enc` suffix.

When the current encrypted index is corrupt and the backup authenticates and
decodes, PasteRail preserves the corrupt file in `Recovery`, copies the verified
backup to a temporary current-index file, validates it again, and atomically renames
it to `history.enc`. The original backup is not modified. This makes the recovered
store writable immediately and allows later captures and queue changes to survive
another restart.

The ordinary test target always injects a per-test `MemoryKeyStore`; reopening tests
reuse that same instance. Real Keychain coverage is isolated in the opt-in
`PasteRailKeychainIntegrationTests` target. Keychain creation handles a concurrent
`errSecDuplicateItem` by reading and validating the existing 32-byte key without
overwriting malformed data.

## Capture limits

- Empty string-only payloads are ignored.
- Payloads larger than 100 MiB are ignored.
- Concealed and transient pasteboard types fail closed.
- Images are normalized into separate PNG originals and thumbnails for storage.

## Storage performance gates

The MVP keeps the JSON index while these automated limits pass:

- 1,000-record initial load below 500 ms
- one ordinary text save below 100 ms
- one duplicate lookup and update below 20 ms

The performance test also reports index size and process resident memory. If these
limits fail on the supported test Macs, storage must move to SQLite before OCR work.

## Verification status

Current status on June 15, 2026:

- Release build: passed without compiler warnings.
- Universal 2 build: passed for `arm64` and `x86_64`.
- `lipo`: reported `x86_64 arm64`.
- Temporary ad-hoc codesign verification: passed.
- Ordinary tests implemented: 48 after adding update compatibility coverage.
- Local tests executed: 0. Neither XCTest nor Swift Testing is present in the
  selected Command Line Tools installation.
- Keychain integration testing remains opt-in and separate.
- Actual Intel Mac execution: not verified.
- Actual clipboard, Accessibility, password-manager exclusion, VoiceOver, dark
  mode, and multi-monitor behavior: not verified.
- Actual Apple Silicon launch: verified from the packaged Universal ZIP; the
  `arm64`-capable app process started successfully and was then terminated.
- Apple Silicon clipboard paste and Accessibility workflow: not verified.
- GitHub Actions CI: prepared but not dispatched because this workspace has no Git
  metadata and the authenticated GitHub account has no PasteRail repository.

CI now prints Xcode, Swift, and macOS SDK versions, reports executed, failed, and
skipped test counts, and fails when fewer than 47 ordinary tests execute. It builds
and verifies the Universal app, prints `lipo` and codesign results, and uploads only
`PasteRail-0.1.0-universal.zip` as the
`PasteRail-0.1.0-universal` artifact. Keychain integration tests run only through
the explicit `workflow_dispatch` option.

Update compatibility coverage creates encrypted history with one stable key-store
instance, reopens it through a new `ClipStore`, verifies the old record, and then
confirms that access with a different key fails without replacing the encrypted
index or payload.

## Verification history

- Earlier on June 15, 2026, the installed Swift compiler and SDK builds did not
  match, so package manifest compilation failed before source type checking.
- After Command Line Tools were reinstalled, application source compilation,
  Release linking, `arm64` and `x86_64` builds, Universal assembly, `lipo`, and
  ad-hoc codesign verification succeeded.
- Local `swift test` then reached and linked the application target but failed at
  `import XCTest` for both test targets. Direct Swift Testing import also failed
  with `error: no such module 'Testing'`.
- Source and application ZIP packaging succeeded. The source archive excludes
  build state and user files; the extracted application ZIP retained both
  architectures and passed strict codesign verification.
