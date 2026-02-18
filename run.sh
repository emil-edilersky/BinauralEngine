#!/bin/bash
# Build and run BinauralEngine as a proper macOS .app bundle
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "Building..."
swift build 2>&1

APP_DIR="$SCRIPT_DIR/.build/BinauralEngine.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp .build/arm64-apple-macosx/debug/BinauralEngine "$MACOS_DIR/"

# Copy resource bundle if it exists
if [ -d ".build/arm64-apple-macosx/debug/BinauralEngine_BinauralEngine.bundle" ]; then
    cp -R ".build/arm64-apple-macosx/debug/BinauralEngine_BinauralEngine.bundle" "$RESOURCES_DIR/"
fi

# Create Info.plist for the app bundle
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>BinauralEngine</string>
    <key>CFBundleIdentifier</key>
    <string>com.binauralengine.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>BinauralEngine</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Launching BinauralEngine.app..."
open "$APP_DIR"
