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
- App-only local storage under `PasteRail`
- Atomic JSON index, previous-index backup, corrupt-index preservation, separate
  payload/thumbnail files, legacy image-file compatibility, private POSIX permissions,
  and guarded orphan cleanup
- AES-256-GCM encryption for the index, payloads, legacy original-image files, and thumbnails;
  GitHub beta builds store the 256-bit key in `Keys/storage.key` under the app's
  Application Support directory instead of using Keychain
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

The ordinary test target injects a per-test `MemoryKeyStore` for encrypted-store
compatibility tests and uses `LocalFileEncryptionKeyStore` for default-key-store
coverage. Real Keychain coverage is isolated in the opt-in
`PasteRailKeychainIntegrationTests` target. Keychain creation handles a concurrent
`errSecDuplicateItem` by reading and validating the existing 32-byte key without
overwriting malformed data. The default GitHub build path does not create
`KeychainEncryptionKeyStore` unless `PASTERAIL_KEYSTORE=keychain` is explicitly set.

## Capture limits

- Empty string-only payloads are ignored.
- Payloads larger than 20 MiB are ignored before any store file is created.
- Concealed and transient pasteboard types fail closed.
- Original image representations remain in the encrypted payload used for paste.
  New records create only a separate encrypted PNG thumbnail of at most 160px;
  they do not duplicate the full image as a normalized PNG. The optional
  `imageFile` field and its migration, recovery, and deletion paths remain for
  compatibility with existing encrypted stores.
- PasteRail stores at most 100 recent history records. Pinned records count toward
  the same limit. When the limit is reached, the oldest unpinned record is removed
  from the authenticated index, encrypted payload, any legacy original image, thumbnail, and
  paste queue after the replacement index is written. If all 100 records are pinned,
  the new capture is rejected and the user is notified.
- Referenced encrypted payload, thumbnail, and legacy image files are limited to
  500 MiB total. The oldest unpinned records are removed until both count and byte
  limits are satisfied. Pinned records are never automatically removed. If pinned
  records prevent enough space from being freed, the new record is rejected.
  Pruning updates the authenticated index and queue before deleting old files;
  index failure restores the previous in-memory state while old files remain.
- Thumbnail previews are decrypted on demand and cached in memory for at most the
  30 most recently used records. The cache is cleared on memory-pressure warnings.

## Storage performance gates

The MVP keeps the JSON index while these automated limits pass:

- 100-record initial load below 500 ms
- one ordinary text save below 100 ms
- one duplicate lookup and update below 20 ms
- 100-record search without visible input stalls
- 101st capture plus automatic pruning without index, payload, image, thumbnail,
  or queue divergence

The performance test also reports index size and process resident memory. If these
limits fail on the supported test Macs, storage must move to SQLite before OCR work.

## Packaging

Do not share a ZIP made from the whole project root. Do not upload files named
like `PasteRail.zip` that were created by compressing the project folder. Root
archives can include `.build`, `ModuleCache`, SwiftPM state, app bundles, logs,
or other local build cache files.

For review, sharing, or upload, use only the file produced by
`Scripts/package-review.sh`: `PasteRail-0.1.0-review.zip`. The script prints the
exact upload target as `Upload this file only: ...` after it validates the
archive. `Scripts/verify-share-archive.sh` can be run on any candidate ZIP and
fails if build caches, app bundles, dSYM files, logs, `.DS_Store`, or other
forbidden artifacts are present.

Source and application artifacts must be created only with
`Scripts/package-source.sh`, `Scripts/package-universal.sh`, or
`Scripts/package-review.sh`.

`package-source.sh` creates a source-only archive from an allow-listed staging
folder and fails if `.build`, `.swiftpm`, `DerivedData`, `ModuleCache`, dSYM
bundles, app bundles, logs, user state, or the Universal app ZIP appear in the
archive. `package-review.sh` creates a small review archive containing only the
source ZIP, Universal app ZIP, README, development record, privacy document, and
manual-test checklist.
It removes any prior review ZIP before rebuilding, always runs source packaging
before Universal packaging, rejects either artifact when a relevant source file is
newer, and does not leave an older review ZIP available after a failed rebuild.
Universal ZIP creation strips resource forks and extended attributes, rejects
AppleDouble, `__MACOSX`, caches, logs, and dSYM content, and requires the archive
to contain only `PasteRail.app`. CI reuses its already verified Universal build
for this packaging check instead of compiling both architectures twice.

`Scripts/package-dmg.sh` always rebuilds the Universal app, verifies its ad-hoc
signature and both architectures, creates a DMG containing `PasteRail.app` and an
Applications shortcut, and runs `hdiutil verify`. This is a local manual-test
artifact only; it is neither Developer ID signed nor notarized.

Direct distribution uses the separate `package-release-dmg.sh` path documented in
`RELEASE.md`. It requires `DEVELOPMENT_TEAM`, `DEVELOPER_ID_APPLICATION`, and
notarytool credentials; signs the app with Hardened Runtime and secure timestamp;
notarizes and staples both the app and final DMG; and verifies them with codesign,
stapler, and Gatekeeper. If the certificate is unavailable, it creates only the
ad-hoc test DMG and exits unsuccessfully rather than reporting a release.

The legacy optional Keychain service `io.pasterail.PasteRail.storage` and account
`primary-aes-gcm-key` remain unchanged for opt-in compatibility and tests. GitHub
beta builds use the local file key at `~/Library/Application Support/PasteRail/Keys/storage.key`
by default, so first launch should not show a Keychain prompt. Existing encrypted
history from older Keychain-backed test builds may fail to authenticate with the
local key; PasteRail preserves the files and offers a user-confirmed data reset
instead of deleting Keychain items or silently replacing encrypted data.

## Manual UI verification checklist

- Pin button click changes only the pinned state and does not paste.
- Queue selection button click changes only queue selection and does not paste.
- Row content click focuses the row and starts the paste path.
- With the search field focused, left/right arrow and Home/End remain text-field
  editing keys.
- With the search field focused, up/down arrow and Page Up/Down move list focus,
  and Enter pastes the focused record by design.

## Verification status

Current status on June 17, 2026:

- Release build: passed locally after removing stale `.build` and `.swiftpm`.
- Universal 2 build: passed locally for `arm64` and `x86_64`.
- `lipo`: reported `x86_64 arm64`.
- Temporary ad-hoc codesign verification: passed locally. This is not a Developer
  ID signature and is not notarization; Gatekeeper can still warn or block the app
  on other Macs.
- Ordinary tests implemented: 97.
- Keychain integration tests implemented: 1 opt-in test.
- Local tests executed: 0. Neither XCTest nor Swift Testing is present in the
  selected Command Line Tools installation.
- `Scripts/run-tests.sh` is the dedicated test entrypoint. It checks for XCTest
  first and fails clearly when the local toolchain cannot import it. Packaging
  scripts do not call this script by default, so a Command Line Tools-only machine
  with the macOS 15 SDK can still build the app and create a manual-test DMG. With
  Command Line Tools for the macOS 27 SDK, `swift build` fails in `PanelView.swift`
  because SwiftUI `@State` and `@FocusState` need Xcode's SwiftUIMacros plugin, so
  local builds and DMG creation need Xcode there.
- GitHub Actions ordinary test gate: requires at least 97 executed ordinary tests.
- Latest GitHub Actions CI for commit `70f4187` executed 59 ordinary tests with
  59 passed, 0 failed, and 0 skipped, then built and verified the Universal app.
- Keychain integration testing remains opt-in and separate.
- Actual Intel Mac execution: not verified.
- Actual clipboard, Accessibility, password-manager exclusion, VoiceOver, dark
  mode, and multi-monitor behavior: not verified.
- Actual Apple Silicon launch: latest rebuilt Universal app was opened on Apple
  Silicon and produced a `PasteRail` process. It exited before termination was
  needed; clipboard and Accessibility workflows remain unverified.
- Apple Silicon clipboard paste and Accessibility workflow: not verified.
- June 17 storage-limit build: Debug, Release, Universal `arm64`/`x86_64`, strict
  ad-hoc codesign, Universal ZIP structure, stale-archive replacement, and review
  ZIP verification passed locally. The manual-test DMG was created and its
  checksum passed `hdiutil verify` during `package-dmg.sh`.
- The June 17 local `swift test --filter PasteRailTests` attempt compiled and
  linked the app target but executed 0 tests because XCTest is unavailable in the
  selected Command Line Tools. The ordinary XCTest suite has not passed locally.
- GitHub CI run `27677174032` for commit `68e86e1` executed all 67 ordinary tests
  with 67 passed, 0 failed, and 0 skipped. Debug, Release, Universal build,
  architecture verification, strict ad-hoc codesign verification, Universal ZIP
  structure validation, and artifact upload passed. The opt-in Keychain integration
  job was skipped as designed.
- CodeQL run `27677173893` for commit `68e86e1` passed Xcode selection, CodeQL init,
  the manual Swift build/extraction step, analyze, and upload.
- Direct-distribution scripts were added on June 17. The local Keychain reported
  zero valid code-signing identities, so Developer ID signing, secure timestamp,
  Apple notarization, stapling, and Gatekeeper acceptance were not executed or
  marked successful. The release script correctly selected its certificate-missing
  fallback, rebuilt the Universal app, and created only the ad-hoc manual-test DMG;
  `hdiutil verify` passed and no `PasteRail-0.1.0-release.dmg` was produced.
- June 26 local-key-store change: the default runtime key store was switched from
  Keychain to `LocalFileEncryptionKeyStore`. The key is stored at
  `~/Library/Application Support/PasteRail/Keys/storage.key` with `0600`
  permissions, and `PASTERAIL_KEYSTORE=keychain` is now the only runtime path that
  selects the legacy Keychain implementation. Five ordinary regression tests were
  added for local-key creation/reuse, invalid key handling, wrong-key recovery,
  and safe data reset. Clean first-launch Keychain-prompt behavior still requires
  manual app execution verification.
- June 26 local packaging path: `build-universal.sh`, `package-universal.sh`,
  `package-review.sh`, and `package-dmg.sh` use build/sign/package verification
  only; they do not require XCTest. They still need a toolchain that can compile
  SwiftUI, which means Xcode when the selected SDK is macOS 27. The recommended
  local manual-test sequence is:

  ```sh
  rm -rf .build .swiftpm
  swift build -c release
  ./Scripts/build-universal.sh
  ./Scripts/package-dmg.sh
  ```
- June 26 first-launch UX change: PasteRail remains an accessory menu bar app,
  but first launch now shows a Welcome alert explaining menu bar status,
  Command-Shift-V, Command-Option-P, local storage, and beta notarization status.
  The status item sets a `PasteRail` tooltip and falls back to the `PR` title if
  the SF Symbol cannot be created. Hot key registration now checks Carbon return
  codes, logs success/failure, and warns the user when a shortcut cannot be
  registered. Manual verification is still required for real menu bar visibility,
  Welcome display, Accessibility settings opening, and shortcut behavior on a
  user Mac.
- June 26 language/accessibility/shortcut diagnostics change: the menu bar menu
  now supports English and Korean through `selectedLanguage`, exposes a fixed set
  of open-panel shortcut choices, rolls back shortcut changes that fail to
  register, and can copy non-sensitive diagnostics. Accessibility permission uses
  `AXIsProcessTrustedWithOptions` with the prompt option and opens the Privacy &
  Security > Accessibility pane, but macOS still requires the user to grant access
  manually. PasteRail cannot silently add itself to the Accessibility list. Running
  directly from a DMG or using an ad-hoc, non-notarized build can make Gatekeeper
  warnings and Accessibility-list appearance less predictable; `/Applications`
  launch remains the manual-test recommendation. Command-Shift-V and other global
  shortcuts can conflict with macOS or other apps, so menu-bar `Open PasteRail`
  remains the fallback path.
- November 9 shortcut, reset, and queue fixes: a failed menu shortcut change now
  keeps the previous shortcut's registration status and shows a one-time alert
  instead of leaving a permanent warning. Shortcut warnings are derived from the
  current open-panel and queue registration state, so a successful open-panel
  change no longer hides a queue shortcut failure, and warnings follow the selected
  language. Selecting the current shortcut again retries registration when it is
  not registered. `Reset PasteRail Data` closes the panel and restarts the store,
  panel, and shortcuts even when deletion fails. Queue pastes run one at a time, so
  two quick Command-Option-P presses paste two consecutive entries instead of the
  first entry twice, and a payload load failure is no longer reported as a sent
  paste. Eight ordinary tests were added, for 88 in total.
- November 9 local verification: this machine has only Command Line Tools with the
  macOS 27 SDK. There, `swift build` fails because SwiftUI `@State` and
  `@FocusState` are macros that need Xcode's SwiftUIMacros plugin, and XCTest is
  unavailable. In a scratch copy that stubbed those two property wrappers in
  `PanelView.swift` and ran the unchanged XCTest file through a small
  XCTest-to-Swift-Testing shim, the app module compiled and all 88 ordinary tests
  passed. A control copy without queue serialization failed the new rapid-queue
  test by pasting the first entry twice. CI remains the authority for the real
  XCTest run.
- November 9 CI correction: the first scratch shim treated `XCTestCase` as
  main-actor isolated. Real XCTest test methods are nonisolated, so CI failed to
  compile tests that call `HotKey.shouldHandleEvent` synchronously. The routing
  check is now `nonisolated`, and the scratch shim matches XCTest's isolation.
- November 9 UX and robustness changes: the Welcome window names the selected
  open-panel shortcut instead of always Command-Shift-V. It shows the
  not-notarized line only when the running app lacks a Developer ID signature; the
  check evaluates Apple's Developer ID code requirement locally and makes no network
  request. Clipboard polling runs in common run-loop modes, so a copy made while a
  menu or modal alert is open is still captured. On macOS 14 and later, PasteRail
  yields activation to the paste target and uses cooperative activation instead of
  the deprecated ignoring-other-apps option. Model errors, paste failure reasons,
  and store recovery notices now come from the English and Korean string table, and
  the Settings window text is localized. Seven ordinary tests were added, for 95 in
  total.
- November 9 CI result: run `42634059954` for commit `2b75ae5` executed 88
  ordinary tests with 88 passed, 0 failed, and 0 skipped, then passed the Debug,
  Release, Universal build, verification, packaging, and product-code checks.
- November 9 legacy data and documentation: `Reset PasteRail Data` now also
  removes `~/Library/Application Support/io.pasterail.PasteRail`, which the first
  test build created with a Keychain-backed key and current builds never read. Both
  folder names are validated before anything is deleted. PRIVACY.md, README, and
  `Scripts/run-tests.sh` now state that Command Line Tools for the macOS 27 SDK
  cannot build the SwiftUI panel. Two ordinary tests were added, for 97 in total.

CI now prints Xcode, Swift, and macOS SDK versions, reports executed, failed, and
skipped test counts, and fails when fewer than 97 ordinary tests execute. It builds
and verifies the Universal app, prints `lipo` and codesign results, and uploads only
`PasteRail-0.1.0-universal.zip` as the
`PasteRail-0.1.0-universal` artifact. Keychain integration tests run only through
the explicit `workflow_dispatch` option.

CodeQL uses manual Swift build mode. It selects Xcode in a stable priority order
(`Xcode_16.4`, then `Xcode_16.3`, then `Xcode.app`), cleans SwiftPM build state,
and performs a single debug build for extractor database creation before analyze.

Update compatibility coverage creates encrypted history with one stable key-store
instance, reopens it through a new `ClipStore`, verifies the old record, and then
confirms that access with a different key fails without replacing the encrypted
index or payload.

## Verification history

- On June 17, 2026, Debug application compilation/linking, Release compilation,
  Universal `arm64`/`x86_64` assembly, `lipo`, strict ad-hoc codesign verification,
  and review packaging passed with the image-storage and packaging changes. Local
  `swift test` still executed 0 tests because the selected Command Line Tools does
  not provide `XCTest`; this is not recorded as a test pass. The prior GitHub run
  covered 59 tests, so CI must run the current ordinary test suite before release validation
  is current.

- Earlier on June 15, 2026, the installed Swift compiler and SDK builds did not
  match, so package manifest compilation failed before source type checking.
- After Command Line Tools were reinstalled, application source compilation,
  Release linking, `arm64` and `x86_64` builds, Universal assembly, `lipo`, and
  ad-hoc codesign verification succeeded.
- Local `swift test` then reached and linked the application target but failed at
  `import XCTest` for both test targets. Direct Swift Testing import also failed
  with `error: no such module 'Testing'`.
- `Scripts/run-tests.sh` now preserves this distinction: it fails early with a
  clear XCTest-unavailable message on Command Line Tools-only installations, while
  app build and manual DMG packaging remain usable.
- Source and application ZIP packaging succeeded. The source archive excludes
  build state and user files; the extracted application ZIP retained both
  architectures and passed strict codesign verification.
