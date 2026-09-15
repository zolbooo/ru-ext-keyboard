#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
app="$PWD/.build/NativePunctuation/NativePunctuation.app"
mkdir -p "$app"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -g -O0 -fobjc-arc -isysroot "$sdk" -target arm64-apple-ios18.0-simulator -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics Tests/NativePunctuation/main.m -o "$app/NativePunctuation"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.keyboard.native-punctuation-probe</string><key>CFBundleExecutable</key><string>NativePunctuation</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleName</key><string>NativePunctuation</string><key>UILaunchScreen</key><dict/></dict></plist>
PLIST
codesign --force --sign - "$app"
