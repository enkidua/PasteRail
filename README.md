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
- The app contains no network client, analytics, advertising, updater, payment,
  subscription, or donation feature.
- Protected pasteboard types and common password manager applications are excluded.
- Accessibility permission is required only to send the paste keyboard shortcut.

See `PRIVACY.md` for details.

## Build

Requirements:

- macOS 13 or later
- A stable Xcode release that supports the selected macOS SDK

Run tests:

```sh
swift test
```

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

Create a local manual-test DMG:

```sh
./Scripts/package-dmg.sh
```

This produces `PasteRail-0.1.0-universal.dmg` containing the Universal app and an
Applications shortcut. The app is ad-hoc signed for local testing; the DMG and app
are not Developer ID signed or notarized. Follow `MANUAL_TEST.md` before treating
the build as release-ready.

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
