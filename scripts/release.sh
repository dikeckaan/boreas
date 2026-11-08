#!/bin/bash
# Builds, signs, notarizes and packages Boreas.
#
#   scripts/release.sh <version> [--skip-notarize] [--publish]
#
#   --skip-notarize  dry run: builds, signs and packs the DMG but does not talk to Apple's notary service.
#                    The result is NOT distributable (Gatekeeper rejects it).
#   --publish        after everything passed, creates the GitHub release v<version> with the DMG attached.
#
# Everything lands under build/release/ (gitignored). Notarization uses the keychain profile
# "boreas-notary"; create it once with:
#
#   xcrun notarytool store-credentials boreas-notary
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROFILE=boreas-notary
VERSION=""
SKIP_NOTARIZE=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n 2,13p "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) [ -z "$VERSION" ] && VERSION="$arg" || { echo "unexpected argument: $arg" >&2; exit 2; } ;;
  esac
done
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version> [--skip-notarize] [--publish]" >&2; exit 2; }
if [ "$SKIP_NOTARIZE" = 1 ] && [ "$PUBLISH" = 1 ]; then
  echo "error: --publish cannot be combined with --skip-notarize (an unnotarized build must not be published)" >&2
  exit 2
fi

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

OUT="$ROOT/build/release"
ARCHIVE="$OUT/Boreas.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Boreas.app"
ZIP="$OUT/Boreas-$VERSION.zip"
DMG="$OUT/Boreas-$VERSION.dmg"

if [ "$SKIP_NOTARIZE" = 1 ]; then
  warn "DRY RUN (--skip-notarize): nothing is sent to Apple. The app and DMG will NOT pass Gatekeeper and must not be distributed."
else
  step "Checking notarytool credentials"
  if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    cat >&2 <<MSG
error: the notarytool keychain profile "$PROFILE" is missing or invalid.
Create it once (Apple ID, app-specific password and Team ID are entered by you):

    xcrun notarytool store-credentials $PROFILE

or run this script with --skip-notarize for a dry run.
MSG
    exit 1
  fi
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "1/9 xcodegen generate"
xcodegen generate

step "2/9 swift test (BoreasCore)"
( cd Packages/BoreasCore && swift test )

step "3/9 xcodebuild archive ($VERSION)"
xcodebuild archive -project Boreas.xcodeproj -scheme Boreas -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates MARKETING_VERSION="$VERSION" | tail -n 5

step "4/9 xcodebuild -exportArchive (Developer ID)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -allowProvisioningUpdates | tail -n 5
[ -d "$APP" ] || { echo "error: export did not produce $APP" >&2; exit 1; }

step "5/9 codesign verification"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGN_INFO=$(codesign -dv --verbose=2 "$APP" 2>&1)
echo "$SIGN_INFO" | grep -E 'Authority=|TeamIdentifier='
echo "$SIGN_INFO" | grep -q 'Authority=Developer ID Application' || { echo "error: app is not signed with Developer ID" >&2; exit 1; }

if [ "$SKIP_NOTARIZE" = 1 ]; then
  step "6/9 notarize + staple app: SKIPPED (--skip-notarize)"
else
  step "6/9 notarize app"
  ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

step "7/9 build DMG"
"$ROOT/scripts/make-dmg.sh" "$APP" "$VERSION" "$DMG"

step "8/9 sign / notarize DMG"
DMG_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
if [ -n "$DMG_IDENTITY" ]; then
  codesign --force --sign "$DMG_IDENTITY" --timestamp "$DMG"
  codesign --verify --verbose=2 "$DMG"
else
  echo "No local Developer ID Application identity: the DMG itself is not codesigned."
  echo "(Gatekeeper evaluates the notarized + stapled app inside; the DMG ticket below covers the container.)"
fi
if [ "$SKIP_NOTARIZE" = 1 ]; then
  echo "Notarize + staple DMG: SKIPPED (--skip-notarize)"
else
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

step "9/9 Gatekeeper assessment"
if [ "$SKIP_NOTARIZE" = 1 ]; then
  set +e
  spctl -a -vv -t install "$DMG"; echo "spctl (dmg) exit: $?"
  spctl -a -vv -t exec "$APP"; echo "spctl (app) exit: $?"
  set -e
  warn "Rejection above is EXPECTED in a dry run: the build is not notarized."
else
  spctl -a -vv -t install "$DMG"
  spctl -a -vv -t exec "$APP"
fi

echo
echo "Done: $DMG"
[ "$SKIP_NOTARIZE" = 1 ] && warn "dry run only: NOT notarized, do not distribute."

if [ "$PUBLISH" = 1 ]; then
  step "Publishing GitHub release v$VERSION"
  NOTES="$OUT/release-notes.md"
  cat > "$NOTES" <<MSG
Boreas $VERSION

Open the DMG and drag Boreas to Applications, then approve "Allow in the Background" once. See the README for details.

DMG'yi açıp Boreas'ı Uygulamalar'a sürükleyin, ardından "Arka Planda İzin Ver" onayını bir kez verin. Ayrıntılar için README'ye bakın.

Apple Silicon, macOS 15 or later.
MSG
  gh release create "v$VERSION" "$DMG" --title "Boreas $VERSION" --notes-file "$NOTES"
fi
