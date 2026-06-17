# PasteRail Manual Test Checklist

Use `PasteRail-0.1.0-universal.dmg` only for local manual testing. The contained
app has an ad-hoc signature and is not Developer ID signed or notarized.

## Installation And Launch

- [ ] Run the app on Apple Silicon without Rosetta.
- [ ] Run the app on an Intel Mac when an Intel test environment is available.
- [ ] Confirm the menu bar icon appears.
- [ ] Press Command-Shift-V and confirm the history panel opens.
- [ ] With multiple displays, confirm the panel appears on the display containing the mouse pointer.

## Capture And Browsing

- [ ] Copy and record plain text, a URL, RTF content, and a file reference.
- [ ] Copy and record PNG, JPEG, and TIFF images.
- [ ] Confirm image thumbnails appear without loading full originals in the list.
- [ ] Scroll the single history list with a mouse wheel or trackpad.
- [ ] Search history and exercise every type filter.

## Paste And Queue

- [ ] Paste a selected item into the application that was active before the panel opened.
- [ ] Paste rich text once as unformatted plain text.
- [ ] Confirm FIFO queue order and that the queue advances only after target activation, clipboard write, and Command-V event posting succeed.
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
