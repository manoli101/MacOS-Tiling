#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_NAME="Tyler"
APP_BUNDLE="$ROOT/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

# Create signing cert (skips if already exists)
"$SCRIPT_DIR/create_signing_cert.sh"

# Build
"$SCRIPT_DIR/build.sh"

echo "▶ Installing to $INSTALL_PATH..."
# Kill any running instance
pkill -f "$APP_NAME" 2>/dev/null || true

rm -rf "$INSTALL_PATH"
cp -r "$APP_BUNDLE" "$INSTALL_PATH"

echo "▶ Removing quarantine flag (Gatekeeper bypass)..."
xattr -cr "$INSTALL_PATH" 2>/dev/null || true

echo "▶ Launching..."
open "$INSTALL_PATH"

echo ""
echo "✅ Tyler installed and running."
echo ""
echo "⚠️  First launch: macOS will ask for Accessibility permission."
echo "   → System Settings → Privacy & Security → Accessibility"
echo "   → Enable 'Tyler'"
echo "   → Quit and reopen the app"
echo ""
echo "Shortcuts:  ⌥ (Option) + Arrow keys"
echo "  →   Right half  (repeat → next monitor)"
echo "  ←   Left half   (repeat → prev monitor)"
echo "  ↑   Top half → maximize"
echo "  ↓   Move down / double-press to minimize"
