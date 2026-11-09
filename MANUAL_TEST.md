# PasteRail Manual Test Checklist

Use `PasteRail-0.1.0-universal.dmg` only for local manual testing. The contained
app has an ad-hoc signature and is not Developer ID signed or notarized.

## Installation And Launch

- [ ] Start from a clean `~/Library/Application Support/PasteRail` directory and confirm the app launches directly.
- [ ] Confirm the first launch shows the Welcome window.
- [ ] Confirm the Welcome window says PasteRail is running in the menu bar and names the selected open-panel shortcut and Command + Option + P.
- [ ] Change the open-panel shortcut, choose `Show Welcome`, and confirm the Welcome window names the new shortcut.
- [ ] On this ad-hoc test build, confirm the Welcome window says the build is not notarized. On a Developer ID release build, confirm that line is absent.
- [ ] Click `Open Clipboard Panel` in the Welcome window and confirm the clipboard panel appears.
- [ ] Relaunch after selecting `Don't show again` and confirm the setting is respected.
- [ ] Confirm no macOS Keychain password or access approval prompt appears on first launch.
- [ ] Run the app on Apple Silicon without Rosetta.
- [ ] Run the app on an Intel Mac when an Intel test environment is available.
- [ ] Confirm the menu bar icon appears.
- [ ] Confirm the menu bar icon tooltip is `PasteRail`.
- [ ] Confirm `Open PasteRail` from the menu bar opens the clipboard panel.
- [ ] Confirm `Show Welcome` from the menu bar opens the Welcome window.
- [ ] Confirm `Open Accessibility Settings` opens System Settings.
- [ ] Select `한국어` from the Language menu and confirm menu and Welcome text update.
- [ ] Select `English` from the Language menu and confirm menu and Welcome text update.
- [ ] Confirm the Shortcut menu shows the current shortcut and registration state.
- [ ] Change the shortcut to each built-in option and confirm successful choices take effect immediately.
- [ ] If a shortcut conflicts, confirm PasteRail displays a conflict or failure message and keeps the previous working shortcut.
- [ ] After a failed shortcut change, confirm the Shortcut menu still shows the previous shortcut as registered and the failure warning does not reappear in the Welcome window.
- [ ] If the current shortcut failed to register at launch, select the same shortcut again after closing the conflicting app and confirm it registers.
- [ ] Click `Copy Diagnostics` / `진단 정보 복사` and confirm it copies version, bundle ID, app path, key-store type, language, Accessibility state, shortcuts, macOS version, and architecture without clipboard history content.
- [ ] Click `Request Accessibility Permission` and confirm macOS shows or attempts to show the Accessibility permission prompt.
- [ ] Confirm PasteRail appears in Privacy & Security > Accessibility when launched from `/Applications`; note if DMG-direct launch behaves differently.
- [ ] Press Command-Shift-V and confirm the history panel opens.
- [ ] If Command-Shift-V is already taken by another app or macOS, confirm PasteRail shows a warning and the menu bar still opens the panel.
- [ ] With multiple displays, confirm the panel appears on the display containing the mouse pointer.
- [ ] Install the same build again and confirm existing encrypted history opens without Keychain prompts.
- [ ] If older Keychain-backed test-build data exists, confirm PasteRail shows a recoverable storage message instead of crashing.
- [ ] Use `Reset PasteRail Data`, confirm the warning dialog appears, and verify `~/Library/Application Support/PasteRail` is removed only after confirmation.
- [ ] After reset, copy a new text item and confirm history can be stored again.
- [ ] Reset while the clipboard panel is open and confirm the panel closes, then confirm the shortcuts and menu items still work.
- [ ] Confirm any Gatekeeper warning is understood as unsigned/notarization status, not a Keychain prompt.
- [ ] If the app appears silent, confirm it is running with `pgrep -fl PasteRail`.
- [ ] Inspect launch diagnostics with `log stream --predicate 'process == "PasteRail"' --level debug`.

## Capture And Browsing

- [ ] Copy and record plain text, a URL, RTF content, and a file reference.
- [ ] Copy and record PNG, JPEG, and TIFF images.
- [ ] Confirm image thumbnails appear without loading full originals in the list.
- [ ] Scroll the single history list with a mouse wheel or trackpad.
- [ ] Search history and exercise every type filter.
- [ ] Open the PasteRail menu or the Welcome window, copy text in another app while it stays open, close it, and confirm the copy was recorded.

## Paste And Queue

- [ ] Paste a selected item into the application that was active before the panel opened.
- [ ] Without Accessibility permission, confirm the panel still opens but automatic paste shows a clear permission message.
- [ ] After granting Accessibility permission, confirm automatic paste can proceed.
- [ ] Paste rich text once as unformatted plain text.
- [ ] Confirm FIFO queue order and that the queue advances only after target activation, clipboard write, and Command-V event posting succeed.
- [ ] Queue two items and press Command-Option-P twice quickly. Confirm each item is pasted once, in order.
- [ ] On macOS 14 or later, paste from the panel and confirm the previous app is frontmost again before the text appears.
- [ ] Select `한국어`, quit the target app while the panel is open, paste an item, and confirm the failure message is shown in Korean.
- [ ] Click a pin button and confirm pin state changes without pasting.
- [ ] Click a queue selection button and confirm selection changes without pasting.

## Limits And Security

- [ ] Add a 101st record and confirm the oldest unpinned record is removed.
- [ ] Confirm a clipboard payload larger than 20 MiB is rejected without changing existing history.
- [ ] Confirm referenced encrypted files remain at or below the 500 MiB total limit and pinned records are not automatically deleted.
- [ ] Copy from 1Password or another excluded password manager and confirm no record is created.
- [ ] Confirm pasteboard items containing concealed or transient types are rejected.
- [ ] Restart PasteRail and confirm encrypted history is restored.
- [ ] Monitor network activity and confirm PasteRail makes no network connection.

## Resource Use

- [ ] Observe idle and active CPU use.
- [ ] Scroll image history and observe memory use and thumbnail-cache release under memory pressure.
