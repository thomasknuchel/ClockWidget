#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClockWidget"
DMG_NAME="ClockWidget.dmg"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "🕐 Building $APP_NAME..."

if ! command -v swiftc &>/dev/null; then
    echo "❌ swiftc not found. Run: xcode-select --install"; exit 1
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Convert icon
if [ -d "$SCRIPT_DIR/AppIcon.iconset" ] && command -v iconutil &>/dev/null; then
    iconutil -c icns "$SCRIPT_DIR/AppIcon.iconset" \
        -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    echo "✅ Icon converted"
fi

echo "Compiling..."
swiftc "$SCRIPT_DIR/ClockWidget.swift" \
    -o "$BINARY" \
    -framework AppKit \
    -framework Foundation \
    -O
echo "✅ Compiled"

cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
chmod +x "$BINARY"

# Sign WITHOUT hardened runtime, WITH entitlements
# This is critical for macOS 26 - hardened runtime + ad-hoc sig causes PAC crashes
codesign --force --deep \
    --sign - \
    --options runtime \
    --entitlements "$SCRIPT_DIR/entitlements.plist" \
    "$APP_BUNDLE"
echo "✅ Signed"

# Install
rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_BUNDLE" "/Applications/$APP_NAME.app"
xattr -cr "/Applications/$APP_NAME.app"
echo "✅ Installed"

# Build DMG
echo "Building DMG..."
TMP_DMG="$SCRIPT_DIR/.tmp_$DMG_NAME"
OUT_DMG="$SCRIPT_DIR/$DMG_NAME"
rm -f "$OUT_DMG" "$TMP_DMG"
hdiutil create -size 30m -fs HFS+ -volname "$APP_NAME" "$TMP_DMG" -quiet
MOUNT_POINT=$(hdiutil attach "$TMP_DMG" -readwrite -nobrowse | grep "/Volumes/" | awk '{print $NF}')
cp -R "$APP_BUNDLE" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {400, 100, 900, 420}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set position of item "$APP_NAME.app" of container window to {130, 160}
        set position of item "Applications" of container window to {370, 160}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
hdiutil detach "$MOUNT_POINT" -quiet
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG" -quiet
rm -f "$TMP_DMG"

echo ""
echo "🎉 Done!"
echo "✅ Installed: /Applications/$APP_NAME.app"
echo "✅ DMG: $OUT_DMG"
pkill -f "ClockWidget" 2>/dev/null || true
sleep 1
open "/Applications/$APP_NAME.app"
