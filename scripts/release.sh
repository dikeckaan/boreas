#!/bin/bash
# Builds, signs, notarizes and packages Boreas.
#
#   scripts/release.sh <version> [--skip-notarize] [--publish]
#
#   --skip-notarize  dry run: builds, signs and packs the DMG but does not talk to Apple's notary service.
#                    The result is NOT distributable (Gatekeeper rejects it).
#   --publish        after everything passed, creates the GitHub release v<version> with the DMG attached.
#                    Preflight requires a clean tree, a tag v<version> on HEAD that names the same commit on origin,
#                    a logged-in gh and no existing release of that name.
#
# The DMG is signed, notarized and stapled only when a local "Developer ID Application" identity exists.
# Otherwise it ships unsigned and Gatekeeper's verdict comes from the notarized + stapled app inside.
#
# Everything lands under build/release/ (gitignored). Notarization uses the notarytool keychain
# profile "boreas-notary" when it exists (create it with `xcrun notarytool store-credentials
# boreas-notary`). Without it, the app is notarized through the Apple ID signed in to Xcode
# (Settings > Accounts): `xcodebuild -exportArchive` with destination "upload", then
# `xcodebuild -exportNotarizedApp`. No password is needed on that path.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

PROFILE=boreas-notary
NOTARY_MODE=none
VERSION=""
SKIP_NOTARIZE=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n 2,19p "$0"; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 2 ;;
    *) [ -z "$VERSION" ] && VERSION="$arg" || { echo "unexpected argument: $arg" >&2; exit 2; } ;;
  esac
done
[ -n "$VERSION" ] || { echo "usage: scripts/release.sh <version> [--skip-notarize] [--publish]" >&2; exit 2; }
printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "error: version must look like 1.2.3, got '$VERSION'" >&2; exit 2; }
if [ "$SKIP_NOTARIZE" = 1 ] && [ "$PUBLISH" = 1 ]; then
  echo "error: --publish cannot be combined with --skip-notarize (an unnotarized build must not be published)" >&2
  exit 2
fi

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

# Runs a command with its full output appended to $LOG; on failure prints the last 60 lines of it.
logged() {
  if ! "$@" >>"$LOG" 2>&1; then
    echo "error: command failed: $*" >&2
    echo "--- last 60 lines of $LOG ---" >&2
    tail -n 60 "$LOG" >&2
    exit 1
  fi
}

# notarize <file>: submits, waits, and fails visibly (printing the notary log) unless Accepted.
notarize() {
  local file=$1 json id status
  json=$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait --output-format json) || {
    echo "error: notarytool submit failed" >&2; echo "$json" >&2; exit 1; }
  id=$(printf '%s' "$json" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  status=$(printf '%s' "$json" | python3 -I -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
  echo "notarization $id: $status"
  if [ "$status" != "Accepted" ]; then
    echo "error: notarization of $(basename "$file") ended with status '$status'. Notary log:" >&2
    xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true
    exit 1
  fi
}

OUT="$ROOT/build/release"
ARCHIVE="$OUT/Boreas.xcarchive"
EXPORT="$OUT/export"
APP="$EXPORT/Boreas.app"
ZIP="$OUT/Boreas-$VERSION.zip"
DMG="$OUT/Boreas-$VERSION.dmg"
LOG="$ROOT/build/release-$VERSION.log"
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)

if [ "$SKIP_NOTARIZE" = 1 ]; then
  warn "DRY RUN (--skip-notarize): nothing is sent to Apple. The app and DMG will NOT pass Gatekeeper and must not be distributed."
else
  step "Checking notarization method"
  if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    NOTARY_MODE=profile
    echo "notarytool keychain profile \"$PROFILE\" found"
  else
    NOTARY_MODE=xcode
    echo "no notarytool profile \"$PROFILE\": notarizing through the Apple ID signed in to Xcode"
  fi
fi

if [ "$PUBLISH" = 1 ]; then
  step "Publish preflight"
  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git status --porcelain)" ]; then
    echo "error: the working tree is not clean; commit or stash everything first" >&2; exit 1
  fi
  TAG_COMMIT=$(git rev-parse -q --verify "v$VERSION^{commit}" 2>/dev/null) || { echo "error: tag v$VERSION does not exist locally" >&2; exit 1; }
  [ "$TAG_COMMIT" = "$(git rev-parse HEAD)" ] || { echo "error: tag v$VERSION does not point at HEAD" >&2; exit 1; }
  # The commit the tag names on origin: the peeled entry (annotated tag) or the plain one (lightweight).
  REMOTE_REFS=$(git ls-remote origin "refs/tags/v$VERSION" "refs/tags/v$VERSION^{}" 2>/dev/null) || REMOTE_REFS=""
  REMOTE_COMMIT=$(printf '%s\n' "$REMOTE_REFS" | awk -v t="refs/tags/v$VERSION^{}" '$2 == t { print $1 }')
  [ -n "$REMOTE_COMMIT" ] || REMOTE_COMMIT=$(printf '%s\n' "$REMOTE_REFS" | awk -v t="refs/tags/v$VERSION" '$2 == t { print $1 }')
  [ -n "$REMOTE_COMMIT" ] || { echo "error: tag v$VERSION is not on origin (push it first)" >&2; exit 1; }
  [ "$REMOTE_COMMIT" = "$TAG_COMMIT" ] || {
    echo "error: tag v$VERSION on origin points at $REMOTE_COMMIT, but locally at $TAG_COMMIT (HEAD)" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "error: gh is not logged in (gh auth login)" >&2; exit 1; }
  if gh release view "v$VERSION" >/dev/null 2>&1; then echo "error: release v$VERSION already exists" >&2; exit 1; fi
fi

rm -rf "$OUT"
mkdir -p "$OUT"
: > "$LOG"
echo "full build output: $LOG"

step "1/9 xcodegen generate"
xcodegen generate

step "2/9 swift test (BoreasCore)"
( cd Packages/BoreasCore && swift test )

step "3/9 xcodebuild archive ($VERSION)"
logged xcodebuild archive -project Boreas.xcodeproj -scheme Boreas -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
echo "archived (build number $BUILD_NUMBER)"

step "4/9 xcodebuild -exportArchive (Developer ID)"
logged xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" -allowProvisioningUpdates
[ -d "$APP" ] || { echo "error: export did not produce $APP" >&2; exit 1; }

step "5/9 codesign verification"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGN_INFO=$(codesign -dv --verbose=2 "$APP" 2>&1)
echo "$SIGN_INFO" | grep -E 'Authority=|TeamIdentifier='
echo "$SIGN_INFO" | grep -q 'Authority=Developer ID Application' || { echo "error: app is not signed with Developer ID" >&2; exit 1; }

if [ "$SKIP_NOTARIZE" = 1 ]; then
  step "6/9 notarize + staple app: SKIPPED (--skip-notarize)"
elif [ "$NOTARY_MODE" = profile ]; then
  step "6/9 notarize app (notarytool)"
  ditto -c -k --keepParent "$APP" "$ZIP"
  notarize "$ZIP"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  step "6/9 notarize app (Xcode account)"
  UPLOAD_PLIST="$OUT/ExportOptions-upload.plist"
  cp "$ROOT/scripts/ExportOptions.plist" "$UPLOAD_PLIST"
  plutil -insert destination -string upload "$UPLOAD_PLIST"
  logged xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$OUT/upload" \
    -exportOptionsPlist "$UPLOAD_PLIST" -allowProvisioningUpdates
  echo "uploaded; waiting for Apple (up to 30 minutes)"
  NOTARIZED="$OUT/notarized"
  for attempt in $(seq 1 90); do
    if xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath "$NOTARIZED" \
        -allowProvisioningUpdates >>"$LOG" 2>&1; then
      break
    fi
    if tail -n 20 "$LOG" | grep -qiE 'invalid|rejected'; then
      echo "error: Apple rejected the upload. Last lines of $LOG:" >&2; tail -n 40 "$LOG" >&2; exit 1
    fi
    [ "$attempt" = 90 ] && { echo "error: notarization did not finish in 30 minutes" >&2; tail -n 20 "$LOG" >&2; exit 1; }
    sleep 20
  done
  APP="$NOTARIZED/Boreas.app"
  [ -d "$APP" ] || { echo "error: -exportNotarizedApp did not produce $APP" >&2; exit 1; }
  xcrun stapler validate "$APP"
fi

step "7/9 build DMG"
"$ROOT/scripts/make-dmg.sh" "$APP" "$VERSION" "$DMG"

step "8/9 sign / notarize DMG"
DMG_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
if [ -n "$DMG_IDENTITY" ]; then
  codesign --force --sign "$DMG_IDENTITY" --timestamp "$DMG"
  codesign --verify --verbose=2 "$DMG"
  if [ "$SKIP_NOTARIZE" = 1 ]; then
    echo "Notarize + staple DMG: SKIPPED (--skip-notarize)"
  elif [ "$NOTARY_MODE" != profile ]; then
    echo "Notarize + staple DMG: SKIPPED (needs the notarytool profile; the app inside is notarized)"
  else
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  fi
else
  echo "No local Developer ID Application identity: the DMG ships unsigned and is not notarized."
  echo "Gatekeeper evaluates the notarized + stapled app inside it (checked below on a quarantined copy)."
fi

step "9/9 Gatekeeper assessment"
if [ -n "$DMG_IDENTITY" ]; then
  if [ "$SKIP_NOTARIZE" = 1 ] || [ "$NOTARY_MODE" != profile ]; then
    set +e; spctl -a -vv -t install "$DMG"; echo "spctl (dmg) exit: $?"; set -e
  else
    spctl -a -vv -t install "$DMG"
  fi
fi
# Mount the DMG, copy the app out, mark the copy as downloaded and let Gatekeeper judge it.
GK=$(mktemp -d "${TMPDIR:-/tmp}/boreas-gk.XXXXXX")
GK_DEV=$(hdiutil attach "$DMG" -readonly -noverify -noautoopen -nobrowse -mountpoint "$GK/mnt" 2>/dev/null | awk '/^\/dev\/disk[0-9]+/ {print $1; exit}') || true
[ -d "$GK/mnt/Boreas.app" ] || { echo "error: could not mount $DMG for the Gatekeeper check" >&2; exit 1; }
ditto "$GK/mnt/Boreas.app" "$GK/Boreas.app"
hdiutil detach "$GK_DEV" -quiet || hdiutil detach "$GK_DEV" -force -quiet
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" "$GK/Boreas.app"
set +e
spctl -a -vv -t exec "$GK/Boreas.app"; GK_STATUS=$?
set -e
rm -rf "$GK"
if [ "$SKIP_NOTARIZE" = 1 ]; then
  echo "spctl (quarantined app copy from the DMG) exit: $GK_STATUS"
  warn "Rejection above is EXPECTED in a dry run: the build is not notarized."
elif [ $GK_STATUS -ne 0 ]; then
  echo "error: Gatekeeper rejected the quarantined app copy from the DMG" >&2; exit 1
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
