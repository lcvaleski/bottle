# Contributing

## Building

```sh
brew install xcodegen
xcodegen generate
open Cable.xcodeproj
```

`Cable.xcodeproj` is generated and git-ignored; edit `project.yml` instead of
the project file. Xcode 26 and macOS 14+ are required. Apple Configurator must
be installed to actually talk to a phone, but the app builds without it.

## Working without a phone

Most of the app talks to a real iPhone, but you don't need one to work on the
interface:

```sh
CABLE_DEMO=1 open build/Build/Products/Debug/Cable.app
```

That fills the app with a fake supervised iPhone, a stand-in app list and
generated placeholder icons. `CABLE_DEMO_SCREEN=lock|locked|setup` opens one
screen straight away. Demo mode never runs `cfgutil` and never touches the
network.

## Testing against a phone

Open the activity log (⌘⇧L) and include its output in bug reports — it shows
the exact `cfgutil` invocations and their raw output.

The setup wizard erases the phone. Test it on a device you can wipe, and turn
Find My off first or the erase fails.

## Tests

`CableTests` covers the pure parsing layer — cfgutil JSON, `.mobileconfig`
payloads, keychain labels — using output captured from real devices. Run them
with ⌘U in Xcode or:

```sh
xcodebuild -project Cable.xcodeproj -scheme Cable -destination 'platform=macOS' test
```

When a phone or a new cfgutil version produces output the app mis-parses,
paste the raw JSON from the activity log into a test first.

## Pull requests

- Keep the build warning-free; CI runs the tests and builds a DMG on every PR.
- Match the surrounding style; no formatter is enforced.
- Anything that changes what gets installed on a phone (profile payloads,
  identifiers) needs a note in the PR about compatibility with phones that
  already have the old profile.
