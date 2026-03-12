#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Claumagotchi..."
swift build -c release 2>&1

BINARY=".build/release/Claumagotchi"
APP_DIR="Claumagotchi.app/Contents/MacOS"

RESOURCES_DIR="Claumagotchi.app/Contents/Resources"

echo "Creating app bundle..."
mkdir -p "$APP_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$APP_DIR/"

# Generate app icon from icon.png (transparent, no background)
if [ -f "icon.png" ] && command -v iconutil &>/dev/null; then
    ICONSET="/tmp/claumagotchi-iconset.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    for s in 16 32 64 128 256 512 1024; do
        sips -z $s $s icon.png --out "$ICONSET/tmp_${s}.png" &>/dev/null
    done
    cp "$ICONSET/tmp_16.png"   "$ICONSET/icon_16x16.png"
    cp "$ICONSET/tmp_32.png"   "$ICONSET/icon_16x16@2x.png"
    cp "$ICONSET/tmp_32.png"   "$ICONSET/icon_32x32.png"
    cp "$ICONSET/tmp_64.png"   "$ICONSET/icon_32x32@2x.png"
    cp "$ICONSET/tmp_128.png"  "$ICONSET/icon_128x128.png"
    cp "$ICONSET/tmp_256.png"  "$ICONSET/icon_128x128@2x.png"
    cp "$ICONSET/tmp_256.png"  "$ICONSET/icon_256x256.png"
    cp "$ICONSET/tmp_512.png"  "$ICONSET/icon_256x256@2x.png"
    cp "$ICONSET/tmp_512.png"  "$ICONSET/icon_512x512.png"
    cp "$ICONSET/tmp_1024.png" "$ICONSET/icon_512x512@2x.png"
    rm -f "$ICONSET"/tmp_*.png
    iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET"
fi

cat > Claumagotchi.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Claumagotchi</string>
    <key>CFBundleIdentifier</key>
    <string>com.claumagotchi.app</string>
    <key>CFBundleName</key>
    <string>Claumagotchi</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Built Claumagotchi.app"
