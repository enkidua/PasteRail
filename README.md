# PasteRail

PasteRail is a free, open-source clipboard manager for macOS 13 and later.
It keeps clipboard history entirely on the Mac and provides a single scrolling
panel, search, plain-text paste, and a FIFO paste queue.
The MVP stores at most 100 recent history items, including pinned items.
Each captured clipboard record is limited to 20 MiB. Image originals remain in
the encrypted clipboard payload; only a separate encrypted 160px thumbnail is
created for list display.
Encrypted payloads, thumbnails, and compatible legacy image files are limited to
500 MiB in total. PasteRail removes the oldest unpinned records to make room and
never automatically removes pinned records.

## Status

PasteRail is under active MVP development. It is not yet considered release-ready.
OCR and advanced history management are intentionally deferred until the core
capture, storage, paste-target restoration, and Universal 2 checks pass on real Macs.

## Privacy

- Clipboard contents are stored only in the user's Application Support directory.
- GitHub beta builds use a local key file by default, not the macOS Keychain, so
  first launch should not show a Keychain password or access prompt.
- The app contains no network client, analytics, advertising, updater, payment,
  subscription, or donation feature.
- Protected pasteboard types and common password manager applications are excluded.
- Accessibility permission is required only to send the paste keyboard shortcut.

See `PRIVACY.md` for details.

## Build

Requirements:

- macOS 13 or later
- A stable Xcode release that supports the selected macOS SDK

Run tests in a full Xcode/XCTest environment:

```sh
./Scripts/run-tests.sh
```

PasteRail's current automated tests use XCTest. On some macOS Command Line
Tools-only installations, `swift test` cannot import `XCTest`; in that case local
test execution fails by design and GitHub Actions is the test authority.

With Command Line Tools for the macOS 27 SDK, `swift build` also fails. SwiftUI
`@State` and `@FocusState` became macros there, and their plugin ships only with
Xcode. Install Xcode to build the app or create the manual-test DMG on such a Mac.

Build a local Universal 2 application:

```sh
./Scripts/build-universal.sh
```

The script creates `.build/universal/PasteRail.app` and verifies its executable
with `lipo`.

The generated app uses an ad-hoc signature for local verification only. It is not
signed with an Apple Developer ID and is not notarized. Gatekeeper may warn or
block the app when it is opened on another Mac. A public release, App Store
submission, or general-user distribution requires an appropriate production
signature and Apple notarization.

Gatekeeper warnings are separate from Keychain prompts. PasteRail's GitHub beta
build should not ask for Keychain access on launch; however, macOS may still warn
about opening an unsigned or unnotarized app until a Developer ID release is
available.

Create a local manual-test DMG:

```sh
rm -rf .build .swiftpm
swift build -c release
./Scripts/build-universal.sh
./Scripts/package-dmg.sh
```

This produces `PasteRail-0.1.0-universal.dmg` containing the Universal app and an
Applications shortcut. The app is ad-hoc signed for local testing; the DMG and app
are not Developer ID signed or notarized. The default GitHub beta build uses a
local key file, so it should not show a Keychain prompt. Gatekeeper warnings can
still appear before Developer ID notarization. Follow `MANUAL_TEST.md` before
treating the build as release-ready.

## Launching The App

PasteRail is a menu bar app, so it may not show a Dock icon. On first launch it
shows a Welcome window explaining that it is running in the menu bar. After that,
look for the PasteRail icon in the top-right macOS menu bar.

Use Command-Shift-V to open the clipboard history panel. If that shortcut is
already used by another app or by macOS, PasteRail shows a warning and the panel
can still be opened from the menu bar.

The menu bar menu includes a `Language` submenu for English and Korean. It also
includes a `Shortcut` submenu with these open-panel shortcut choices:

- Command + Shift + V
- Command + Option + V
- Control + Option + V
- Control + Option + Space

If Command-Shift-V does not open the panel, use the menu bar item `Open PasteRail`
as a fallback and choose `Copy Diagnostics` to inspect the registered shortcut
status.

Automatic paste actions require macOS Accessibility permission. Use `Request
Accessibility Permission` from the menu bar to trigger the macOS prompt and open
Privacy & Security > Accessibility. macOS requires the user to allow the app
manually; PasteRail cannot add itself silently. If PasteRail does not appear in
the list, copy `PasteRail.app` to `/Applications`, relaunch it, and click the
request button again. Developer ID notarization is not present in beta builds, so
Gatekeeper warnings and Accessibility-list behavior can be less polished than a
notarized release.

If the app seems to do nothing, check whether it is running:

```sh
pgrep -fl PasteRail
log stream --predicate 'process == "PasteRail"' --level debug
```

Developer ID direct-distribution packaging is documented in `RELEASE.md`. It is
separate from the ad-hoc test DMG and requires an Apple Developer certificate and
notarization credentials.

## Sharing

Do not compress or share the whole project folder. Root archives such as
`PasteRail.zip` can include `.build`, `ModuleCache`, SwiftPM state, app bundles,
logs, or other local build cache files.

For review, upload only the archive produced by:

```sh
./Scripts/package-review.sh
```

The only file intended for sharing is `PasteRail-0.1.0-review.zip`. You can verify
an archive before upload with:

```sh
./Scripts/verify-share-archive.sh PasteRail-0.1.0-review.zip
```

## Shortcuts

- Command-Shift-V: open the history panel
- Command-Option-P: paste the next queue item into the app that is frontmost when
  the shortcut is pressed

## License

PasteRail is available under the MIT License.
