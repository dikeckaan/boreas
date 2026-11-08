#!/bin/sh
# Renders the Boreas app icon and menu bar glyph from docs/design/*.svg into
# App/Resources/Assets.xcassets. Uses only what ships with macOS and Xcode: the SVGs are drawn by
# WebKit (scripts/render-svg.swift, which renders the gaussian-blur filters and keeps the
# transparent corners; `qlmanage -t` draws them on a white background) and scaled with Core Graphics.
#
#   scripts/make-icons.sh
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DESIGN="$ROOT/docs/design"
ASSETS="$ROOT/App/Resources/Assets.xcassets"
ICON="$ASSETS/AppIcon.appiconset"
GLYPH="$ASSETS/MenuBarIcon.imageset"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

mkdir -p "$ICON" "$GLYPH"
rm -f "$ICON"/*.png "$GLYPH"/*.png

# 16 to 64 px (the 16 pt and 32 pt slots) use the simplified artwork, 128 px and up the full one.
swift "$ROOT/scripts/render-svg.swift" \
  "$DESIGN/logo-small.svg" 16 "$ICON/icon_16.png" \
  "$DESIGN/logo-small.svg" 32 "$ICON/icon_32.png" \
  "$DESIGN/logo-small.svg" 64 "$ICON/icon_64.png" \
  "$DESIGN/logo-final.svg" 128 "$ICON/icon_128.png" \
  "$DESIGN/logo-final.svg" 256 "$ICON/icon_256.png" \
  "$DESIGN/logo-final.svg" 512 "$ICON/icon_512.png" \
  "$DESIGN/logo-final.svg" 1024 "$ICON/icon_1024.png" \
  "$DESIGN/menubar-glyph.svg" 18 "$GLYPH/menubar.png" \
  "$DESIGN/menubar-glyph.svg" 36 "$GLYPH/menubar@2x.png"

cat > "$ASSETS/Contents.json" <<'JSON'
{
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

cat > "$ICON/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

cat > "$GLYPH/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "menubar.png", "idiom" : "mac", "scale" : "1x" },
    { "filename" : "menubar@2x.png", "idiom" : "mac", "scale" : "2x" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template" }
}
JSON

for f in "$ICON"/*.png "$GLYPH"/*.png; do
  printf '%s %s\n' "$(sips -g pixelWidth "$f" | awk '/pixelWidth/ { print $2 }')" "${f#"$ROOT"/}"
done
