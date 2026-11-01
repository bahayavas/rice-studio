#!/bin/bash
# Derle, .app paketle, imzala, /Applications'a kopyala, `rice` CLI symlink'ini kur.
#   ./build.sh            derle + kur
#   ./build.sh --no-install
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Rice Studio"
BUNDLE_ID="com.bahayavas.rice-studio"
VERSION="0.1"
OUT="build/$APP_NAME.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/RiceStudio"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/RiceStudio"
# SwiftPM kaynak paketleri (KeyboardShortcuts vb.) varsa yanına
for b in "$(dirname "$BIN")"/*.bundle; do [[ -e "$b" ]] && cp -R "$b" "$OUT/Contents/Resources/"; done

if [[ ! -f build/AppIcon.icns ]]; then
    ICONSET=build/AppIcon.iconset
    mkdir -p "$ICONSET"
    swift tools/make-icon.swift build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>RiceStudio</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Übersicht widget'larını açıp kapatmak için.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier "$BUNDLE_ID" "$OUT"
echo "derlendi: $OUT"

[[ "${1:-}" == "--no-install" ]] && exit 0

osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/$APP_NAME.app"
ditto "$OUT" "/Applications/$APP_NAME.app"
mkdir -p "$HOME/.local/bin"
ln -sf "/Applications/$APP_NAME.app/Contents/MacOS/RiceStudio" "$HOME/.local/bin/rice"
echo "kuruldu: /Applications/$APP_NAME.app  (CLI: ~/.local/bin/rice)"
