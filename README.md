# PasteRail

PasteRail is a free, open-source clipboard manager for macOS 13 and later.
It keeps clipboard history entirely on the Mac and provides a single scrolling
panel, search, plain-text paste, and a FIFO paste queue.

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

## Shortcuts

- Command-Shift-V: open the history panel
- Command-Option-P: paste the next queue item into the app that is frontmost when
  the shortcut is pressed

## License

PasteRail is available under the MIT License.
