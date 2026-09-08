#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
app="$PWD/.build/NativeCursor/NativeCursor.app"
mkdir -p "$app"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun clang -g -O0 -fobjc-arc -isysroot "$sdk" -target arm64-apple-ios18.0-simulator -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics Tests/NativeCursor/main.m Tests/NativeCursor/Trace.m Tests/NativeCursor/MathProbe.m -o "$app/NativeCursor"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.keyboard.native-cursor-probe</string><key>CFBundleExecutable</key><string>NativeCursor</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleName</key><string>NativeCursor</string><key>UILaunchScreen</key><dict/></dict></plist>
PLIST
codesign --force --sign - "$app"
