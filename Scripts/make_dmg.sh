#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_BUNDLE="$ROOT/Tyler.app"
DMG_NAME="Tyler"
DMG_TEMP="$ROOT/${DMG_NAME}-temp.dmg"
DMG_FINAL="$ROOT/${DMG_NAME}.dmg"
STAGING="$ROOT/dmg-staging"

# Build first
bash "$SCRIPT_DIR/build.sh"

echo "▶ Preparing DMG staging..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -r "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "▶ Creating DMG..."
rm -f "$DMG_TEMP" "$DMG_FINAL"
hdiutil create \
    -volname "$DMG_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDRW \
    "$DMG_TEMP"

echo "▶ Mounting to customize layout..."
MOUNT_DIR="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP" | \
    grep -E '^/dev/' | tail -1 | awk '{print $NF}')"
echo "  Mounted at: $MOUNT_DIR"

osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$DMG_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 200, 900, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "Tyler.app" of container window to {150, 150}
        set position of item "Applications" of container window to {350, 150}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT_DIR" -quiet

echo "▶ Compressing to final DMG..."
hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_FINAL"
rm -f "$DMG_TEMP"
rm -rf "$STAGING"

echo "✅ DMG ready: $DMG_FINAL ($(du -sh "$DMG_FINAL" | cut -f1))"
