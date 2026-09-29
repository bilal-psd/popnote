#!/bin/sh
# Builds Popnote.app into ./build and signs it for local use.
set -e
cd "$(dirname "$0")/.."

swift build -c release

APP=build/Popnote.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Popnote" "$APP/Contents/MacOS/Popnote"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.popnote.Popnote</string>
    <key>CFBundleName</key><string>Popnote</string>
    <key>CFBundleDisplayName</key><string>Popnote</string>
    <key>CFBundleExecutable</key><string>Popnote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.3.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Popnote sends notes to Apple Notes when you ask it to.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: fine for running on this Mac, not for distribution.
codesign --force --sign - "$APP"
echo "Built $APP"
