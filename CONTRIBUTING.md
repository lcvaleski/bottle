# Contributing

## Building

```sh
brew install xcodegen
xcodegen generate
open Bottle.xcodeproj
```

`Bottle.xcodeproj` is generated and git-ignored; edit `project.yml` instead of
the project file. Xcode 26 and macOS 14+ are required. Apple Configurator must
be installed to actually talk to a phone, but the app builds without it.

## Testing against a phone

Most of the app only works with a real, supervised iPhone plugged in. Open the
activity log (⌘⇧L) and include its output in bug reports — it shows the exact
`cfgutil` invocations and their raw output.

The supervision wizard erases the phone. Test it on a device you can wipe.

## Pull requests

- Keep `swift build`-style warnings at zero; CI builds every PR.
- Match the surrounding style; no formatter is enforced.
- Anything that changes what gets installed on a phone (profile payloads,
  identifiers) needs a note in the PR about compatibility with phones that
  already have the old profile.
