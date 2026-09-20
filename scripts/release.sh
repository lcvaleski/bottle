#!/bin/bash
# Build, sign, notarize, and package Bottle.
#
#   scripts/release.sh <version> [build-number]
#
# Produces dist/Bottle-<version>.dmg (+ dist/appcast.xml when a Sparkle key is present).
#
# Environment — all optional. Missing pieces are skipped with a warning, so the
# script runs locally with nothing set and produces an ad-hoc-signed DMG:
#   SIGNING_IDENTITY          "Developer ID Application: Name (TEAMID)". Default "-" (ad-hoc).
#   NOTARY_KEY_PATH           App Store Connect API key (.p8)      ┐
#   NOTARY_KEY_ID             its Key ID                            ├ all three → notarize + staple
#   NOTARY_ISSUER_ID          its Issuer ID                         ┘
#   SPARKLE_PRIVATE_KEY_FILE  EdDSA private key (generate_keys -x) → signs the DMG, writes appcast.xml
#   SPARKLE_PUBLIC_ED_KEY     matching public key, baked into Info.plist
#   SPARKLE_FEED_URL          appcast URL, baked into Info.plist
#   DOWNLOAD_URL_PREFIX       where the DMG will be hosted (for the appcast enclosure URL)
set -euo pipefail

VERSION="${1:?usage: release.sh <version> [build-number]}"
BUILD_NUMBER="${2:-1}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/release"
DIST="$ROOT/dist"
APP_NAME="Bottle"
DMG_NAME="$APP_NAME-$VERSION.dmg"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

cd "$ROOT"
rm -rf "$DIST" && mkdir -p "$DIST"

log "Generating project"
xcodegen generate --quiet

log "Building $APP_NAME $VERSION ($BUILD_NUMBER) signed with '$SIGNING_IDENTITY'"
BUILD_SETTINGS=(
  MARKETING_VERSION="$VERSION"
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://example.invalid/appcast.xml}"
  SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
)
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  BUILD_SETTINGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp=none")
fi
BUILD_LOG="$ROOT/build/release-build.log"
mkdir -p "$(dirname "$BUILD_LOG")"
if ! xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -derivedDataPath "$DERIVED" -destination 'platform=macOS' \
  "${BUILD_SETTINGS[@]}" build > "$BUILD_LOG" 2>&1; then
  grep -E "error:|BUILD" "$BUILD_LOG" >&2 || tail -50 "$BUILD_LOG" >&2
  echo "build failed; full log: $BUILD_LOG" >&2
  exit 1
fi
grep -E "warning: .*\.swift|BUILD SUCCEEDED" "$BUILD_LOG" || true

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "build failed: $APP missing" >&2; exit 1; }

log "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

NOTARIZE=false
if [[ -n "${NOTARY_KEY_PATH:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    warn "notary credentials set but signing is ad-hoc; skipping notarization"
  else
    NOTARIZE=true
  fi
else
  warn "no notary credentials; the DMG will be blocked by Gatekeeper on other Macs"
fi

notarize() {
  local path="$1"
  log "Notarizing $(basename "$path")"
  xcrun notarytool submit "$path" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait
}

if $NOTARIZE; then
  ZIP="$DIST/$APP_NAME.zip"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  rm "$ZIP"
  xcrun stapler staple "$APP"
fi

log "Building DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DIST/$DMG_NAME"
rm -rf "$STAGING"

if [[ "$SIGNING_IDENTITY" != "-" ]]; then
  codesign --sign "$SIGNING_IDENTITY" --timestamp "$DIST/$DMG_NAME"
fi
if $NOTARIZE; then
  notarize "$DIST/$DMG_NAME"
  xcrun stapler staple "$DIST/$DMG_NAME"
  spctl --assess --type open --context context:primary-signature -v "$DIST/$DMG_NAME"
fi

if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  log "Generating Sparkle appcast"
  SPARKLE_BIN="$(find "$DERIVED/SourcePackages/artifacts" -type f -name generate_appcast -exec dirname {} ; | head -1)"
  [[ -n "$SPARKLE_BIN" ]] || { echo "Sparkle tools not found under $DERIVED/SourcePackages" >&2; exit 1; }
  "$SPARKLE_BIN/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" \
    ${DOWNLOAD_URL_PREFIX:+--download-url-prefix "$DOWNLOAD_URL_PREFIX"} \
    -o "$DIST/appcast.xml" "$DIST"
else
  warn "SPARKLE_PRIVATE_KEY_FILE not set; skipping appcast"
fi

log "Done"
ls -la "$DIST"
