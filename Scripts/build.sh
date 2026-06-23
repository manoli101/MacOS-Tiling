#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
APP_NAME="Tyler"
APP_BUNDLE="$ROOT/$APP_NAME.app"

echo "▶ Building $APP_NAME (release)..."
cd "$ROOT"
swift build -c release 2>&1

echo "▶ Assembling .app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$ROOT/.build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Include icon if it exists
if [ -f "$ROOT/Tyler.icns" ]; then
    cp "$ROOT/Tyler.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.user.tyler</string>
    <key>CFBundleName</key>
    <string>Tyler</string>
    <key>CFBundleDisplayName</key>
    <string>Tyler</string>
    <key>CFBundleExecutable</key>
    <string>Tyler</string>
    <key>CFBundleVersion</key>
    <string>1.1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Tyler needs Accessibility access to move and resize application windows.</string>
</dict>
</plist>
PLIST

# Sign with stable cert if available, otherwise ad-hoc.
# Stable cert = macOS remembers Accessibility permission across reinstalls.
# Run Scripts/create_signing_cert.sh once to create it.
CERT_NAME="MacOSTiling Dev"
if security find-certificate -c "$CERT_NAME" ~/Library/Keychains/login.keychain-db &>/dev/null; then
    echo "▶ Code signing (MacOSTiling Dev cert)..."
    codesign --deep --force -s "$CERT_NAME" "$APP_BUNDLE"
else
    echo "▶ Code signing (ad-hoc — run Scripts/create_signing_cert.sh to fix permission resets)..."
    codesign --deep --force -s - "$APP_BUNDLE"
fi

echo "✅ Built: $APP_BUNDLE"
