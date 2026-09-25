#!/bin/bash
# Screenshot every screen Cable can show, using CABLE_DEMO so no phone is needed.
#
#   scripts/screens.sh [output-directory]
#
# Each entry is "state:Readable Name". The state is CABLE_DEMO_SCREEN; the app
# jumps straight there on launch.
set -uo pipefail

OUT="${1:-$HOME/Desktop/Cable Screens}"
APP="$(cd "$(dirname "$0")/.." && pwd)/build/Build/Products/Debug/Cable.app"
[[ -d "$APP" ]] || { echo "Build Cable first: xcodebuild -project Cable.xcodeproj -scheme Cable -configuration Debug -derivedDataPath build build" >&2; exit 1; }

SCREENS=(
  "noconfigurator:01 Needs Apple Configurator"
  "nophone:02 No iPhone plugged in"
  "needstrust:03 iPhone not trusted"
  "setup:04 First run"
  "wizard-checks:05 Wizard checks"
  "wizard-options:06 Wizard options"
  "wizard-running:07 Wizard running"
  "wizard-failed:08 Wizard failed"
  "wizard-done:09 Wizard done"
  "identity-found:10 Key found on this Mac"
  "identity-none:11 No key on this Mac"
  "identity-mismatch:12 Key is for another iPhone"
  "apps-fresh:13 Apps nothing blocked"
  "apps-blocked:14 Apps blocked"
  "apps-pending:15 Apps unsaved changes"
  "apps-search:16 Apps search empty"
  "sites-empty:17 Websites empty"
  "sites:18 Websites blocked"
  "lock:19 Lock sheet"
  "lock-done:20 Locked handoff"
  "locked:21 Locked"
  "unlocking:22 Unlocking countdown"
  "released:23 Ready to unblock"
  "log:24 Activity log"
)

# Window id of Cable's real window, so nothing else can end up in frame.
read -r -d '' WINID_SRC <<'SWIFT'
import CoreGraphics
import Foundation
guard let l = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in l {
    guard let o = w[kCGWindowOwnerName as String] as? String, o == "Cable",
          let id = w[kCGWindowNumber as String] as? Int,
          let b = w[kCGWindowBounds as String] as? [String: Any],
          let h = b["Height"] as? Double, h > 200 else { continue }
    print(id); exit(0)
}
exit(2)
SWIFT
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf '%s' "$WINID_SRC" > "$TMP/winid.swift"
swiftc -O -o "$TMP/winid" "$TMP/winid.swift" 2>/dev/null

mkdir -p "$OUT"
for entry in "${SCREENS[@]}"; do
  state="${entry%%:*}"
  name="${entry#*:}"
  printf '%-34s' "$name"
  pkill -x Cable 2>/dev/null
  sleep 1.5
  # A fresh window frame every time, so one screen can't inherit another's size.
  defaults delete com.coventrylabs.cable 2>/dev/null
  CABLE_DEMO=1 CABLE_DEMO_SCREEN="$state" open -a "$APP"
  sleep 6
  osascript -e 'tell application "Cable" to activate' >/dev/null 2>&1
  sleep 2
  if id="$("$TMP/winid")"; then
    screencapture -x -o -l "$id" "$OUT/$name.png" 2>/dev/null && echo "ok" || echo "capture failed"
  else
    echo "no window"
  fi
done
pkill -x Cable 2>/dev/null
echo
echo "$(ls -1 "$OUT" | wc -l | tr -d ' ') screenshots in $OUT"
