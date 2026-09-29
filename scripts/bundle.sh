#!/bin/sh
# Builds Popnote.app into ./build: one universal binary (Apple Silicon and
# Intel), the icons drawn by scripts/icon.swift, and the bundled Nerd Font.
set -e
cd "$(dirname "$0")/.."

VERSION=$(cat VERSION)
# 1.2.3 -> 10203, so every release has a higher build number.
BUILD=$(echo "$VERSION" | awk -F. '{ print $1 * 10000 + $2 * 100 + $3 }')

for arch in arm64 x86_64; do
    swift build -c release --triple "$arch-apple-macosx14.0"
done

APP=build/Popnote.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/Popnote" \
    .build/arm64-apple-macosx/release/Popnote \
    .build/x86_64-apple-macosx/release/Popnote

# Icons: one drawing, rendered to every size macOS asks for.
ICONS=build/icons
rm -rf "$ICONS"
swift scripts/icon.swift "$ICONS" >/dev/null
ICONSET="$ICONS/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$ICONS/AppIcon-rounded.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double "$ICONS/AppIcon-rounded.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$ICONS/MenuBarIcon.pdf" "$APP/Contents/Resources/"

cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.bilal-psd.popnote</string>
    <key>CFBundleName</key><string>Popnote</string>
    <key>CFBundleDisplayName</key><string>Popnote</string>
    <key>CFBundleExecutable</key><string>Popnote</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>ATSApplicationFontsPath</key><string>Fonts</string>
    <key>NSHumanReadableCopyright</key><string>© Mohammed Bilal. MIT licence.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: required to run on Apple Silicon, but not a Developer ID,
# so macOS asks for approval the first time a downloaded copy is opened.
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"
