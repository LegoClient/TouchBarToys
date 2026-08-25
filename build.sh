#!/bin/bash
# Builds TouchBarToys.app. Command Line Tools are enough, no Xcode required.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TouchBarToys.app"
BIN="$APP/Contents/MacOS/TouchBarToys"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O \
  -import-objc-header Sources/App/PrivateAPI.h \
  -o "$BIN" \
  Sources/Toys/*.swift Sources/App/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>TouchBarToys</string>
  <key>CFBundleDevelopmentRegion</key>  <string>en</string>
  <key>CFBundleDisplayName</key>       <string>Touch Bar Toys</string>
  <key>CFBundleExecutable</key>        <string>TouchBarToys</string>
  <key>CFBundleIdentifier</key>        <string>com.touchbartoys.app</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key>           <string>1</string>
  <key>LSMinimumSystemVersion</key>    <string>11.0</string>
  <key>LSUIElement</key>               <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Touch Bar Toys reads what Spotify is playing so it can show it on the Touch Bar.</string>
  <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

mkdir -p "$APP/Contents/Resources/en.lproj"
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
echo "built $APP"
