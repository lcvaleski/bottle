# Cable

A small macOS app that blocks apps and websites on your own iPhone, using
Apple's own supervision mechanism through Apple Configurator's `cfgutil`.

**Website: [cableblocker.com](https://cableblocker.com)** · The site lives in
[`site/`](site/) and deploys to Vercel on every push to `main`.

The app was called Bottle until v0.1.1. Everything is the same tool with a
different name; see [Renamed from Bottle](#renamed-from-bottle) for what that
means if you used a build from before.

## What it does

- **Blocks apps.** They vanish from the Home Screen, App Library and Spotlight
  and can't be opened. Data is untouched — unblock and the app comes back as it
  was.
- **Blocks websites** in Safari and in-app browsers.
- **Makes the block stick.** By default the profile can't be removed from the
  iPhone's own Settings, so unblocking means plugging into this Mac.
- **Optionally hands the keys away** (see [Lock](#lock)) so unblocking needs a
  delay you choose, or someone you choose — not a click.

## Why supervision, and why it erases the phone

Per-app blocking (`com.apple.applicationaccess` → `blockedAppBundleIDs`) and
website filtering (`com.apple.webcontent-filter`) only work on a **supervised**
device. Apple only lets a device become supervised while it is freshly erased
(`cfgutil prepare` is "initial configuration of freshly erased devices").
Supervision survives a backup restore, so Cable does:

1. `cfgutil backup` — encrypted or not, whatever the phone is set to
2. `cfgutil erase`
3. wait for the reboot
4. `cfgutil prepare --supervised --name <org> --host-cert supervision-cert.der`
5. `cfgutil restore-backup --source <UDID> [--password …]`
6. `cfgutil get isSupervised`

After that every call passes `-C supervision-cert.der -K supervision-key.der`,
which is what authorizes this Mac to manage the phone.

If the phone is **already** supervised — by Apple Configurator, say — Cable
skips all of that and just needs the existing key.

## Requirements

- macOS 14+, Xcode 26 (for building)
- [Apple Configurator](https://apps.apple.com/app/id1037126344) from the Mac App
  Store. Cable calls `/Applications/Apple Configurator.app/Contents/MacOS/cfgutil`
  directly; you don't need to install the automation tools symlink.
- `xcodegen` (`brew install xcodegen`) to regenerate the project
- `dmgbuild` (`pip install dmgbuild`) only to build a styled DMG

## Build

```sh
xcodegen generate
open Cable.xcodeproj        # Run in Xcode
# or
xcodebuild -project Cable.xcodeproj -scheme Cable -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Cable.app
```

The app is unsandboxed on purpose: it spawns `cfgutil` and `openssl`, and reads
`~/Library/Application Support/MobileSync/Backup`.

### Working without a phone

`CABLE_DEMO=1` fills the app with a fake supervised iPhone, a stand-in app list
and generated placeholder icons, so the interface can be worked on and
screenshotted with nothing plugged in. `CABLE_DEMO_SCREEN=lock|locked|setup`
opens one screen straight away.

```sh
CABLE_DEMO=1 open build/Build/Products/Debug/Cable.app
```

Demo mode never runs `cfgutil` and never touches the network.

## Layout

```
Cable/
  CableApp.swift                 entry point, menu commands
  Core/
    ProcessRunner.swift          async subprocess, line streaming, cancellation
    CfgUtil.swift                cfgutil wrapper: JSON parsing, serialized calls, -C/-K
    Device.swift                 device model + loose JSON coercion
    DeviceMonitor.swift          polls `cfgutil list` every 3 s
    SupervisionIdentity.swift    generate / import-from-keychain / import-.p12 → DER, escrow, migration
    SupervisionWizard.swift      backup → erase → prepare → restore state machine
    RestrictionsProfile.swift    builds the .mobileconfig (apps, websites, removal password)
    ProfileLibrary.swift         matches installed profiles to local .mobileconfig files
    AppRestrictionsModel.swift   installed apps, live-vs-edited state, apply/remove
    Suggestions.swift            the usual culprits, narrowed to what's installed
    IconCache.swift              get-app-icon → downscaled per-phone cache
    LockService.swift            HTTP client for the lock service + on-disk lock record
    LockModel.swift              lock / poll / unlock state machine
    Updater.swift                Sparkle wiring (inert unless CI baked in a feed + key)
    AppModel.swift               wiring
    ActivityLog.swift            every command and its output, for the log pane
    Demo.swift                   fake state for CABLE_DEMO
  UI/
    ContentView.swift            single window, toolbar identity, window sizing, empty states
    DeviceView.swift             routes to setup / identity / block list
    BlockListView.swift          the app icon grid, websites tab, action bar
    Style.swift                  StatusChip, AppTile, AppIconView, NoticeBanner, bottom bar
    SupervisionWizardView.swift  preflight checklist, progress list
    IdentitySetupView.swift      pick a Configurator keychain key or open a .p12
    LockViews.swift              lock sheet, locked screen, countdown, QR, copyable link
    LogView.swift                raw cfgutil output, copyable
CableTests/                      parsing, profile building, suggestions (33 tests)
packaging/                       DMG background + dmgbuild settings + icon generator
scripts/release.sh               build → sign → notarize → DMG → appcast
site/                            cableblocker.com: landing page, lock pages, lock API
```

There is no sidebar: people connect one iPhone, so the device lives in the
toolbar and the window is the task at hand.

## Supervision identity

Cable needs the certificate + private key of whichever organization supervised
the phone. Three ways to get one, all handled in the app:

- **Already supervised with Apple Configurator on this Mac** — Cable finds the
  "Apple Configurator: <org>" identity in the login keychain, exports it as
  PKCS#12 via `SecItemExport`, and unpacks it with `/usr/bin/openssl` (LibreSSL;
  Apple's PKCS#12 uses RC2-40, which Homebrew's OpenSSL 3 refuses without
  `-legacy` — don't swap the binary).
- **Supervised from another Mac** — export it there (Apple Configurator →
  Settings → Organizations → Export Supervision Identity) and open the `.p12`.
- **Not supervised yet** — the wizard generates a self-signed identity.

Files land in `~/Library/Application Support/Cable/SupervisionIdentity/`
(`supervision-cert.der`, `supervision-key.der` at 0600, `organization.txt`).
**Back these up.** Without the key this Mac can no longer manage the phone, and
re-supervising means another erase.

The interface never says "certificate" or "supervision identity" — it talks
about which computer is allowed to change the phone.

## Lock

`site/api/` is a small service on Vercel functions, one AES-256-GCM encrypted
JSON blob per lock in a private Vercel Blob store (`LOCK_SECRET` encrypts at
rest). When the user clicks **Lock…**:

1. `POST /api/locks` creates the lock and returns a random removal password once.
2. The app reinstalls the profile with a `com.apple.profileRemovalPassword`
   payload (and `PayloadRemovalDisallowed: false`, since the password is now the
   door).
3. `PUT /api/locks/:id/identity` escrows the Mac's supervision identity — and
   only after the server confirms it holds a copy does the app delete its own.

Unblocking happens from the phone at `/l/<id>#<token>`: `POST …/unlock` starts
the timer, `…/cancel` stops it, `…/approve` (a separate approver token)
releases immediately. Once released, `GET …/:id` returns the password (and
`?identity=1` the identity). The user types it into Settings → General → VPN &
Device Management, and the Mac app's **Finish Here** pulls the identity back and
returns to switch mode.

Neither the password nor the identity is useful without the phone in hand — both
only work over the cable or in Settings — so a leak of the store is a nuisance,
not a takeover. No accounts and no payments yet; delays from 5 minutes to 30
days.

`LockService.baseURL` is still `https://corephone.org`, the site's previous
domain, because links handed to already-locked phones contain those URLs. That
domain must keep serving for as long as any lock made with it is live.

## Existing profiles

The phone only reports a profile's identifier and name, never its payload. To
show what an existing profile blocks, Cable Spotlight-searches this Mac for
`.mobileconfig` files, matches `PayloadIdentifier`, and reads the app list from
the file. **Take Over** folds that list into Cable's own profile so the old one
can be removed. Profiles with no matching file show "Cable can't read what this
blocks". Signed (CMS-wrapped) profiles aren't parsed yet.

Restriction selections are remembered per phone in `UserDefaults`
(`restrictions.<UDID>`), including what is actually live on the phone, so the
app can show pending changes rather than implying everything is applied.
Backups go where Finder puts them:
`~/Library/Application Support/MobileSync/Backup/<UDID>`.

## Renamed from Bottle

The app, bundle id (`com.coventrylabs.cable`) and profile identifier
(`com.coventrylabs.cable.app-restrictions`) all changed with the rename. Two
things make that safe for anyone who used an earlier build:

- `RestrictionsProfile.legacyIdentifiers` still lists the old profile
  identifiers, so an existing block is **replaced** on the next Apply rather
  than stacked alongside the new one.
- On first launch the supervision key moves from
  `~/Library/Application Support/Bottle/` and saved selections are read once
  from the old `com.coventrylabs.bottle` defaults domain.

## Releasing

`scripts/release.sh <version> [build]` builds a Release app, re-signs Sparkle's
nested helpers, signs and notarizes the app, wraps it in a styled DMG,
notarizes and staples that, and writes a Sparkle appcast. With nothing
configured it produces an ad-hoc-signed DMG in `dist/` — good for local
testing, blocked by Gatekeeper everywhere else.

Real releases happen in GitHub Actions (`.github/workflows/release.yml`): push
a tag like `v0.2.0` and it publishes a GitHub Release with the notarized DMG
and `appcast.xml`. Each release ships two names — `Cable-<version>.dmg`, which
the appcast references, and a stable `Cable.dmg`, so a download link never has
to name a version:

```
https://github.com/lcvaleski/cable/releases/latest/download/Cable.dmg
```

One-time setup — add these as repository secrets:

| Secret | Where it comes from |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | a **Developer ID Application** certificate exported as `.p12`, then `base64 -i cert.p12 \| pbcopy`. Only an Account Holder can create one. |
| `DEVELOPER_ID_P12_PASSWORD` | the password you chose when exporting |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | App Store Connect → Users and Access → Integrations → **Team Keys** → generate with Developer access; paste the `.p8` contents |
| `SPARKLE_PRIVATE_KEY` | after one local build: `build/release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle.key`, then paste the file's contents |
| `SPARKLE_PUBLIC_ED_KEY` | the public key that same `generate_keys` run printed |

Keep the Sparkle private key somewhere safe outside the repo; updates signed
with any other key are rejected by every installed copy.

Every push and PR also runs `.github/workflows/ci.yml`, which runs the tests and
does the same build ad-hoc.

Notarization rejects Sparkle's `Updater.app`, `Autoupdate` and XPC services
because Xcode leaves them signed by the Sparkle project, so the release script
re-signs them inside-out before signing the app. See
[`packaging/README.md`](packaging/README.md) for the DMG window.

## Verified on a real iPhone (iOS 26.6.1, cfgutil 2.20)

- `list` / `get` JSON shapes, including `Errors` nested **inside** `Output`
- `installedApps` keys: `bundleIdentifier`, `displayName`, `itunesName`, `bundleVersion`
- `configurationProfiles` keys: `identifier`, `displayName`, `version`
- Keychain identity import → `install-profile` with `-C/-K` hides the app immediately
- `get-app-icon` writes to `$PWD` from the environment, **not** the process's
  working directory — `ProcessRunner` sets both
- The whole Lock round trip: server password → profile with the removal-password
  payload → identity escrowed and deleted locally → timer → password typed into
  Settings → apps back

## Not yet verified

The **setup wizard** is marked Experimental in the app: it has only run on a
couple of phones. If it stops partway, Apple Configurator can finish the job —
every step is a standard `cfgutil` operation, so the phone is never left
somewhere it can't be recovered from.

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
- Bundle IDs in `Suggestions.usualSuspects` are confirmed for the big ones
  (Instagram, TikTok, Reddit, YouTube, Snapchat, Netflix); the dating and
  betting apps are unconfirmed, so one may simply fail to appear.

## What survives the erase

Cable's backup is an ordinary local backup, so Apple's rules apply:

- **Encrypted backup** (Finder → your iPhone → General → Encrypt local backup):
  keeps saved passwords, Health data, Wi-Fi passwords, call history.
- **Unencrypted backup:** Apple deliberately omits all of the above. The wizard
  warns when the phone reports `backupWillBeEncrypted: false`, because that one
  checkbox is the difference between keeping every app login and losing it.
- **Either way:** Apple Pay cards don't restore — they're device-bound tokens
  and have to be re-added in Wallet. Face ID and Touch ID enrolment is redone.
  Downloaded music and podcasts re-download.
- **The eSIM stays.** `cfgutil erase` only removes it with `--esim`, which Cable
  never passes.

The end-to-end result of Cable's own `prepare` → `restore-backup` ordering
hasn't been watched through on a real phone yet — see below.

## Known limits

- Find My must be off before the erase; `cfgutil` can't check Activation Lock,
  so the wizard asks the user to confirm.
- Only the Mac holding the identity can manage the phone. Cable does not pass
  `--forbid-pairing`, so Finder sync still works.
- Phone, Messages and Settings can't be hidden; iOS ignores the attempt.
- Allow-only mode ("hide everything except these") has no interface for now.
  `RestrictionsProfile` still builds the payload and saved state never restores
  into it, since there would be no way back out.
- Blocking a website doesn't block that service's app, and vice versa.
- Erasing the phone always clears everything Cable did. That's Apple's rule,
  and it's why nothing here can leave a phone stuck.

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Apple. iPhone, Mac and Apple
Configurator are trademarks of Apple Inc.
