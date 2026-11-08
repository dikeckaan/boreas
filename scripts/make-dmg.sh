#!/bin/bash
# Packs Boreas.app into a styled drag-and-drop DMG (app on the left, /Applications shortcut on
# the right, "Kutup Işığı" background with an arrow between them).
#
#   scripts/make-dmg.sh <Boreas.app> <version> <out.dmg> [--update-template]
#
# --update-template stores the .DS_Store of a successful Finder layout as scripts/dmg/DS_Store.template
# (tracked). A normal build never rewrites that file.
#
# Uses only the macOS toolchain: hdiutil, osascript (Finder lays the window out), SetFile, tiffutil
# and scripts/render-svg.swift. Layout: window 660x420, icon size 128, Boreas.app at (165,200),
# Applications at (495,200).
#
# The Finder layout needs a GUI session and Automation permission (System Settings > Privacy &
# Security > Automation: allow your terminal to control Finder). If Finder scripting is denied, the
# script falls back to scripts/dmg/DS_Store.template (the .DS_Store captured from the last successful
# layout) and, failing that, ships an unstyled window and says so. The finished DMG is attached
# once more and the icon positions are read back and compared.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

UPDATE_TEMPLATE=0
POSITIONAL=()
for a in "$@"; do
  case "$a" in
    --update-template) UPDATE_TEMPLATE=1 ;;
    *) POSITIONAL+=("$a") ;;
  esac
done
[ ${#POSITIONAL[@]} -eq 3 ] || { echo "usage: scripts/make-dmg.sh <Boreas.app> <version> <out.dmg> [--update-template]" >&2; exit 2; }
APP=$(cd "$(dirname "${POSITIONAL[0]}")" && pwd)/$(basename "${POSITIONAL[0]}")
VERSION=${POSITIONAL[1]}
OUT=${POSITIONAL[2]}
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
[ -d "$APP" ] || { echo "error: $APP not found" >&2; exit 1; }

VOL=Boreas
WIN_W=660; WIN_H=420
APP_X=165; APP_Y=200; APPS_X=495; APPS_Y=200
DMG_DIR="$ROOT/scripts/dmg"
WORK="$ROOT/build/dmg"
STAGE="$WORK/stage"
RW="$WORK/rw.dmg"
TEMPLATE="$DMG_DIR/DS_Store.template"
LAYOUT=unknown   # finder | template | none

note() { printf '[make-dmg] %s\n' "$*"; }
warn() { printf '[make-dmg] WARNING: %s\n' "$*" >&2; }

if [ -e "/Volumes/$VOL" ]; then
  echo "error: /Volumes/$VOL is already mounted; eject it first (the Finder layout addresses the disk by name)." >&2
  exit 1
fi

# --- 1. Background: PNG @1x/@2x rendered from the SVG, combined into a multi-resolution TIFF -----
note "background"
if [ ! -f "$DMG_DIR/background.png" ] || [ ! -f "$DMG_DIR/background@2x.png" ]; then  # tracked PNGs: delete them to re-render after editing the SVG
  swift "$ROOT/scripts/render-svg.swift" \
    "$DMG_DIR/background.svg" ${WIN_W}x${WIN_H} "$DMG_DIR/background.png" \
    "$DMG_DIR/background.svg" $((WIN_W*2))x$((WIN_H*2)) "$DMG_DIR/background@2x.png"
fi

rm -rf "$WORK"; mkdir -p "$STAGE/.background"
# The 1x image must be 72 dpi and the 2x one 144 dpi, or -cathidpicheck refuses to combine them.
sips -s dpiWidth 72 -s dpiHeight 72 "$DMG_DIR/background.png" --out "$WORK/bg1.png" >/dev/null
sips -s dpiWidth 144 -s dpiHeight 144 "$DMG_DIR/background@2x.png" --out "$WORK/bg2.png" >/dev/null
tiffutil -cathidpicheck "$WORK/bg1.png" "$WORK/bg2.png" -out "$STAGE/.background/background.tiff" >/dev/null

# --- 2. Staging folder ---------------------------------------------------------------------------
note "staging"
ditto "$APP" "$STAGE/Boreas.app"
ln -s /Applications "$STAGE/Applications"
ICNS=$(ls "$APP"/Contents/Resources/*.icns 2>/dev/null | head -n 1 || true)
if [ -n "$ICNS" ]; then cp "$ICNS" "$STAGE/.VolumeIcon.icns"; else warn "no .icns in the app bundle; volume icon skipped"; fi

SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 24 ))
note "creating writable image (${SIZE_MB} MB)"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size ${SIZE_MB}m -ov "$RW" >/dev/null

detach() {
  local dev=$1 i
  for i in 1 2 3 4 5; do hdiutil detach "$dev" -quiet 2>/dev/null && return 0; sleep 2; done
  hdiutil detach "$dev" -force -quiet
}

attach() { # attach <image> [extra args]; prints the device node
  local img=$1; shift
  hdiutil attach "$img" -noverify -noautoopen "$@" | awk '/^\/dev\/disk[0-9]+/ {print $1; exit}'
}

DEV=$(attach "$RW" -readwrite)
trap 'hdiutil detach "$DEV" -force -quiet 2>/dev/null || true' EXIT
MNT="/Volumes/$VOL"
[ -d "$MNT" ] || { echo "error: $MNT did not mount" >&2; exit 1; }

SetFile -a V "$MNT/.background" 2>/dev/null || true

# --- 3. Finder layout ----------------------------------------------------------------------------
note "Finder layout"
# Finder bounds include the title bar (28 pt with the toolbar hidden), so add it to get a 660x420 content area.
TITLEBAR=28
LEFT=200; TOP=120
set +e
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$LEFT, $TOP, $((LEFT+WIN_W)), $((TOP+TITLEBAR+WIN_H))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "Boreas.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    delay 2
    close
    open
    delay 2
  end tell
end tell
OSA
OSA_STATUS=$?
set -e

if [ $OSA_STATUS -eq 0 ]; then
  # Finder flushes .DS_Store lazily; wait for it and for the window to be closed.
  osascript -e 'tell application "Finder" to close every window whose name is "'"$VOL"'"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do [ -s "$MNT/.DS_Store" ] && break; sleep 1; done
  sync; sleep 2
  if [ -s "$MNT/.DS_Store" ]; then
    LAYOUT=finder
    if [ "$UPDATE_TEMPLATE" = 1 ]; then
      cp "$MNT/.DS_Store" "$TEMPLATE"
      note "Finder layout applied; .DS_Store saved to scripts/dmg/DS_Store.template"
    else
      note "Finder layout applied"
    fi
  else
    warn "Finder reported success but wrote no .DS_Store"
  fi
fi

if [ "$LAYOUT" != finder ]; then
  if [ -s "$TEMPLATE" ]; then
    cp "$TEMPLATE" "$MNT/.DS_Store"
    LAYOUT=template
    warn "Finder scripting unavailable (osascript status $OSA_STATUS); using the saved scripts/dmg/DS_Store.template."
  else
    LAYOUT=none
    warn "Finder scripting unavailable (osascript status $OSA_STATUS) and no saved layout exists. The DMG will have NO custom window layout."
    warn "Fix: System Settings > Privacy & Security > Automation: allow your terminal (or osascript) to control Finder, then rebuild."
  fi
fi

# Volume icon: set after the Finder layout, because Finder removes .VolumeIcon.icns while it rewrites the window.
if [ -n "$ICNS" ]; then
  cp "$ICNS" "$MNT/.VolumeIcon.icns"
  SetFile -a C "$MNT"
fi

sync
detach "$DEV"
trap - EXIT

# --- 4. Compress ---------------------------------------------------------------------------------
note "compressing (ULFO)"
rm -f "$OUT"; mkdir -p "$(dirname "$OUT")"
hdiutil convert "$RW" -format ULFO -ov -o "$OUT" >/dev/null
rm -f "$RW"
hdiutil verify "$OUT" >/dev/null
note "built $OUT ($(du -h "$OUT" | cut -f1))"

# --- 5. Read the layout back from the finished image ---------------------------------------------
if [ "$LAYOUT" = none ]; then
  warn "layout verification skipped (no layout)"
  exit 0
fi
note "verifying layout"
DEV=$(attach "$OUT" -readonly)
trap 'hdiutil detach "$DEV" -force -quiet 2>/dev/null || true' EXIT
[ -d "$MNT" ] || { echo "error: $MNT did not mount" >&2; exit 1; }
[ -f "$MNT/.background/background.tiff" ] && note "background.tiff present" || warn "background.tiff missing in the image"
[ -f "$MNT/.VolumeIcon.icns" ] && note ".VolumeIcon.icns present" || warn ".VolumeIcon.icns missing in the image"
if python3 -I -c 'import sys; d=open(sys.argv[1],"rb").read(); sys.exit(0 if (b"BKGD" in d or b"pBBk" in d) else 1)' "$MNT/.DS_Store"; then
  note ".DS_Store carries a background record"
else
  warn ".DS_Store has no background record"
fi
set +e
POS=$(osascript <<OSA 2>&1
tell application "Finder"
  tell disk "$VOL"
    open
    delay 2
    set a to position of item "Boreas.app" of container window
    set b to position of item "Applications" of container window
    set s to icon size of icon view options of container window
    set v to current view of container window
    set r to {item 1 of a, item 2 of a, item 1 of b, item 2 of b, s, v as text}
    close
    return r
  end tell
end tell
OSA
)
POS_STATUS=$?
set -e
detach "$DEV"; trap - EXIT
if [ $POS_STATUS -ne 0 ]; then
  warn "could not read the layout back: $POS"
else
  note "read back (appX, appY, appsX, appsY, iconSize, view): $POS"
  EXPECT="$APP_X, $APP_Y, $APPS_X, $APPS_Y, 128, icon view"
  if [ "$POS" = "$EXPECT" ]; then note "layout matches expectation ($LAYOUT)"; else warn "layout differs from expected: $EXPECT"; fi
fi
