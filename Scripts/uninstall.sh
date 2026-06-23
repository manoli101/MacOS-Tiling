#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MacOSTiling"
INSTALL_PATH="/Applications/$APP_NAME.app"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.user.macos-tiling.plist"

echo "▶ Stopping MacOS Tiling..."
pkill -f "$APP_NAME" 2>/dev/null || true

echo "▶ Removing app bundle..."
rm -rf "$INSTALL_PATH"

# Remove launch agent if it exists
if [ -f "$LAUNCH_AGENT" ]; then
    launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
    rm -f "$LAUNCH_AGENT"
    echo "▶ Removed launch agent (login item)"
fi

echo ""
echo "✅ MacOS Tiling uninstalled."
echo ""
echo "Note: To remove from Accessibility list, go to:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  and remove 'MacOS Tiling' manually."
