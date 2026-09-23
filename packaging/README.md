# Installer packaging

`dmg-settings.py` is a [dmgbuild](https://dmgbuild.readthedocs.io) settings file.
dmgbuild writes the `.DS_Store` itself, so the installer window looks the same on
a laptop and on a CI runner — no Finder AppleScript, no `create-dmg`.

`dmg-background.png` is generated, not hand-drawn:

```sh
swiftc -O -o /tmp/make-bg packaging/make-background.swift
/tmp/make-bg packaging
```

It is deliberately a 1× 600×424 PNG. A multi-resolution TIFF (`tiffutil
-cathidpicheck`) is the "correct" way to get a crisp Retina background, but
Finder renders it at 2× its intended size, which pushes the layout off-screen.

`volume.icns` is the app icon, so the mounted disk shows the Bottle icon.

The layout assumes Finder may show its ~26pt status bar at the bottom
(`show_status_bar = False` is not always honoured), so nothing is drawn below
340pt.
