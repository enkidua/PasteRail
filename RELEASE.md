# PasteRail Direct Distribution

PasteRail uses Developer ID direct distribution, not the Mac App Store. The release
path preserves the fixed bundle identifier `io.pasterail.PasteRail` and produces a
Universal 2 app containing `arm64` and `x86_64`.

## Required Signing Identity

Install a valid `Developer ID Application` certificate and private key in the
login Keychain. Set:

```sh
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"
export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (YOUR_TEAM_ID)"
```

The script verifies that the resulting signature reports this Team ID, the fixed
bundle ID, Hardened Runtime, and a secure timestamp.

## Notarization Credentials

Preferred: store credentials once with `notarytool` and use a Keychain profile.

```sh
xcrun notarytool store-credentials "PasteRail-notary" \
  --apple-id "developer@example.com" \
  --team-id "$DEVELOPMENT_TEAM" \
  --password "APP_SPECIFIC_PASSWORD"
export NOTARYTOOL_PROFILE="PasteRail-notary"
```

Alternatively set all of these for the current process:

```sh
export APPLE_ID="developer@example.com"
export APP_SPECIFIC_PASSWORD="your-app-specific-password"
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"
```

Do not commit credentials, passwords, certificates, or private keys.

## Build Commands

Local ad-hoc test DMG:

```sh
./Scripts/package-test-dmg.sh 0.1.0
```

Developer ID direct-distribution DMG:

```sh
./Scripts/package-release-dmg.sh 0.1.0
```

The release script performs these checks:

1. Builds and verifies the Universal 2 app.
2. Re-signs it with Developer ID, Hardened Runtime, and secure timestamp.
3. Verifies Bundle ID, Team ID, signature, runtime flag, and timestamp.
4. Submits an app ZIP with `xcrun notarytool submit --wait`.
5. Staples and validates the app, then runs `spctl --assess`.
6. Creates and Developer ID-signs `PasteRail-0.1.0-release.dmg`.
7. Notarizes, staples, validates, codesign-verifies, and Gatekeeper-assesses the DMG.

`Scripts/notarize-release.sh <submission> [staple-target]` may also be used for
an individual notarization submission.

If the requested certificate is absent, `package-release-dmg.sh` creates only the
ad-hoc test DMG and exits unsuccessfully. That result is not a release build.

## Keychain Compatibility

GitHub beta builds do not use Keychain for PasteRail clipboard-history encryption
keys by default. They store the AES-GCM key in:

`~/Library/Application Support/PasteRail/Keys/storage.key`

This improves first-launch usability for unsigned GitHub distribution, but it is a
lower security level than Keychain storage. Recommend FileVault and a protected Mac
user account. The app still contains the legacy Keychain implementation for
explicit opt-in testing:

```sh
PASTERAIL_KEYSTORE=keychain open PasteRail.app
```

Do not change these legacy optional Keychain identifiers:

- Service: `io.pasterail.PasteRail.storage`
- Account: `primary-aes-gcm-key`

Existing records from older Keychain-backed test builds may not open in the local
key-file build. PasteRail must preserve the files and show a recoverable reset
message rather than overwrite keys or delete encrypted history. PasteRail does not
automatically delete legacy Keychain items; remove them manually with Keychain
Access or:

```sh
security delete-generic-password -s io.pasterail.PasteRail.storage -a primary-aes-gcm-key
```
