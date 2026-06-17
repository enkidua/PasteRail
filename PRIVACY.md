# PasteRail Privacy

PasteRail processes clipboard data locally on the user's Mac.

## Data collection

PasteRail does not collect analytics, identifiers, usage measurements, crash
reports, advertising data, or personal information. It does not transmit
clipboard contents or application metadata to any server.

## Network access

PasteRail has no network feature, update client, remote logging SDK, advertising
SDK, or telemetry SDK.

## Local storage

History metadata, clipboard payloads, and thumbnails are stored under:

`~/Library/Application Support/io.pasterail.PasteRail`

The storage directory is restricted to the current user. Clipboard payloads,
including original image representations, thumbnails, and the metadata index
containing titles and search text are encrypted with AES-256-GCM. New image
records do not create a second full-size PNG file. Legacy encrypted original-image
files remain readable and are retained or removed with their owning records. The
encryption key is generated locally and stored in the macOS Keychain as a
device-only application secret.

PasteRail stores at most 100 records, accepts at most 20 MiB of original clipboard
payload per record, and limits referenced encrypted payload, thumbnail, and legacy
image files to 500 MiB total. To make room it removes the oldest unpinned records;
pinned records are never removed automatically. If pinned records prevent enough
space from being freed, the new clipboard record is rejected and existing data is
preserved.

Index writes are atomic, the previous encrypted index is retained as a backup, and
a damaged index or ciphertext is preserved for recovery rather than silently
discarded. If the Keychain key is unavailable or authentication fails, PasteRail
does not delete the affected files.

When upgrading a legacy plaintext store, PasteRail first creates and authenticates
the encrypted replacement and an additional AES-GCM encrypted recovery copy. The
legacy plaintext file is removed only after both encrypted forms can be decrypted
and verified. Recovery copies use random `.enc` filenames and do not contain
plaintext titles, search terms, clipboard bytes, or original paths.

APFS and solid-state storage do not provide PasteRail with a reliable way to prove
that deleted plaintext blocks are physically overwritten. FileVault is strongly
recommended to protect data at rest, including filesystem snapshots and storage
blocks that may outlive a logical file deletion.

## Sensitive content

PasteRail rejects concealed and transient pasteboard types. Common password
manager bundle identifiers are excluded by default. Source application detection
is fail-closed around application activation transitions because macOS does not
attach a universally reliable source process to every clipboard change.

## Accessibility

Accessibility permission is used to reactivate the previous application and send
Command-V. If permission is unavailable, PasteRail does not alter the clipboard.
