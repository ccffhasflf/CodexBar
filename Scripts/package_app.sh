#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
DESTINATION="${1:-.build/CodexBar Lite.app}"
mkdir -p "$DESTINATION/Contents/MacOS" "$DESTINATION/Contents/Resources"
cp "$BIN_DIR/CodexBarLite" "$DESTINATION/Contents/MacOS/CodexBarLite"
cp Icon.icns "$DESTINATION/Contents/Resources/Icon.icns"
cp LICENSE "$DESTINATION/Contents/Resources/LICENSE"
cat > "$DESTINATION/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.ccffhasflf.codexbarlite</string>
<key>CFBundleName</key><string>CodexBar Lite</string>
<key>CFBundleDisplayName</key><string>CodexBar Lite</string>
<key>CFBundleExecutable</key><string>CodexBarLite</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>Icon</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$DESTINATION/Contents/Info.plist"
codesign --force --sign - "$DESTINATION"
codesign --verify --strict "$DESTINATION"
printf 'Built %s\n' "$DESTINATION"
