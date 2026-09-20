# Bottle

A small macOS app that supervises your own iPhone with Apple Configurator's
`cfgutil`, then lets you block or allow-list the apps on it.

## Why supervision, and why it erases the phone

Hiding or allow-listing apps (`com.apple.applicationaccess` →
`blockedAppBundleIDs` / `allowListedAppBundleIDs`) only works on a
**supervised** device. Apple only lets a device become supervised while it is
freshly erased (`cfgutil prepare` is "initial configuration of freshly erased
devices"). Supervision survives a backup restore, so Bottle does:

1. `cfgutil backup` — encrypted or not, whatever the phone is set to
2. `cfgutil erase`
3. wait for the reboot
4. `cfgutil prepare --supervised --name <org> --host-cert supervision-cert.der`
5. `cfgutil restore-backup --source <UDID> [--password …]`
6. `cfgutil get isSupervised`

After that every call passes `-C supervision-cert.der -K supervision-key.der`,
which is what authorizes this Mac to manage the phone.

## Requirements

- macOS 14+, Xcode 26 (for building)
- [Apple Configurator](https://apps.apple.com/app/id1037126344) from the Mac App
  Store. Bottle calls `/Applications/Apple Configurator.app/Contents/MacOS/cfgutil`
  directly; you don't need to install the automation tools symlink.
- `xcodegen` (`brew install xcodegen`) to regenerate the project.

## Build

```sh
xcodegen generate
open Bottle.xcodeproj        # Run in Xcode
# or
xcodebuild -project Bottle.xcodeproj -scheme Bottle -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Bottle.app
```

The app is unsandboxed on purpose: it spawns `cfgutil` and `openssl`, and
reads `~/Library/Application Support/MobileSync/Backup`.

## Releasing

`scripts/release.sh <version> [build]` builds a Release app, signs it, notarizes
it, wraps it in a DMG, and writes a Sparkle appcast. With nothing configured it
produces an ad-hoc-signed DMG in `dist/` — good for local testing, blocked by
Gatekeeper everywhere else.

The real releases happen in GitHub Actions (`.github/workflows/release.yml`):
push a tag like `v0.2.0` and it publishes a GitHub Release with the notarized
DMG and `appcast.xml`. The app checks
`https://github.com/<owner>/<repo>/releases/latest/download/appcast.xml` for
updates, and a marketing site can link to
`https://github.com/<owner>/<repo>/releases/latest/download/Bottle-<version>.dmg`
or simply the releases page.

One-time setup — add these as repository secrets:

| Secret | Where it comes from |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | Xcode → Settings → Accounts → Manage Certificates → **Developer ID Application** → export `.p12`, then `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_P12_PASSWORD` | the password you chose when exporting |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect → Users and Access → Integrations → **Team Keys** → generate with Developer access; paste the `.p8` contents |
| `SPARKLE_PRIVATE_KEY` | after one local build: `build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle.key` and paste the file's contents |
| `SPARKLE_PUBLIC_ED_KEY` | the public key that same `generate_keys` run printed |

Keep the Sparkle private key somewhere safe outside the repo; updates signed
with any other key are rejected by every installed copy.

Every push and PR also runs `.github/workflows/ci.yml`, which does the same
build ad-hoc and uploads the DMG as an artifact.

## Layout

```
Bottle/
  BottleApp.swift                  entry point
  Core/
    ProcessRunner.swift            async subprocess with line streaming + cancellation
    CfgUtil.swift                  cfgutil wrapper, JSON parsing, serialized calls
    Device.swift                   device model + loose JSON coercion
    DeviceMonitor.swift            polls `cfgutil list` every 3 s
    SupervisionIdentity.swift      generate / import-from-keychain / import-.p12 → DER cert + key
    SupervisionWizard.swift        the backup → erase → prepare → restore state machine
    RestrictionsProfile.swift      builds the .mobileconfig; list of Apple bundle IDs
    ProfileLibrary.swift           matches installed profiles to local .mobileconfig files
    AppRestrictionsModel.swift     loads installedApps + profiles, installs/removes profiles
    AppModel.swift                 wiring
    IconCache.swift                get-app-icon → downscaled per-phone cache
    Updater.swift                  Sparkle wiring (inert unless CI baked in a feed + key)
  UI/
    ContentView.swift              split view, sidebar, empty states
    DeviceView.swift               header + routing to wizard / identity setup / restrictions
    IdentitySetupView.swift        pick a Configurator keychain identity or import a .p12
    SupervisionWizardView.swift    preflight checklist, step list, controls
    AppRestrictionsView.swift      block/allow picker
    LogView.swift                  raw cfgutil output, copyable
```

## Supervision identity

Bottle needs the certificate + private key of whichever organization supervised
the phone. Three ways to get one, all handled in the app:

- **Already supervised with Apple Configurator on this Mac** — Bottle finds the
  "Apple Configurator: <org>" identity in the login keychain, exports it as
  PKCS#12 via `SecItemExport`, and unpacks it with `/usr/bin/openssl` (LibreSSL;
  Apple's PKCS#12 uses RC2-40, which Homebrew's OpenSSL 3 refuses without
  `-legacy` — don't swap the binary).
- **Supervised from another Mac** — export it there (Apple Configurator →
  Settings → Organizations → Export Supervision Identity) and import the `.p12`.
- **Not supervised yet** — the wizard generates a self-signed identity.

Files land in `~/Library/Application Support/Bottle/SupervisionIdentity/`
(`supervision-cert.der`, `supervision-key.der` at 0600, `organization.txt`).
**Back these up.** Without the key this Mac can no longer manage the phone, and
re-supervising means another erase.

## Existing profiles

The phone only reports a profile's identifier and name, never its payload. To
show what an existing profile blocks, Bottle Spotlight-searches this Mac for
`.mobileconfig` files, matches `PayloadIdentifier`, and reads the app list from
the file. "Add to Bottle" folds that list into Bottle's own profile so the old
one can be removed. Profiles with no matching file show "Contents unknown".
Signed (CMS-wrapped) profiles aren't parsed yet.

Restriction selections are remembered per phone in `UserDefaults`
(`restrictions.<UDID>`). Backups go where Finder puts them:
`~/Library/Application Support/MobileSync/Backup/<UDID>`.

## Verified on a real iPhone (iOS 26.6.1, cfgutil 2.20)

- `list` / `get` JSON shapes, including `Errors` nested inside `Output`
- `installedApps` keys: `bundleIdentifier`, `displayName`, `itunesName`, `bundleVersion`
- `configurationProfiles` keys: `identifier`, `displayName`, `version`
- Keychain identity import → `install-profile` with `-C/-K` hides the app immediately

## Not yet verified (needs an unsupervised phone) — wizard is marked Experimental in the app

- **prepare → restore-backup ordering.** Apple Configurator's own Prepare flow
  supports restoring a backup afterward, and the phone is still at Setup
  Assistant after `prepare`, so `restore-backup` should accept it. If it
  refuses with "must be freshly erased", restore from Finder; supervision
  persists either way.
- **`--skip-*` flags.** None are passed, so the user walks through Setup
  Assistant after the restore. `--skip-all` was deliberately avoided in case it
  drops the phone straight to the Home Screen before the restore.
- Whether `prepare` accepts a self-signed openssl identity (vs. one made by
  Apple Configurator).

## Known limits

- Find My must be off before the erase; cfgutil can't check Activation Lock, so
  the wizard asks the user to confirm.
- Only one Mac (the one holding the identity) can manage the phone. Check
  "Allow devices to pair with other computers" isn't needed — Bottle does not
  pass `--forbid-pairing`, so Finder sync still works.
- Blocking `com.apple.mobilephone`, Settings, etc. isn't offered; iOS ignores it.
