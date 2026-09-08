#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
device="${1:?Usage: bash Tests/SpaceCursor/run.sh BOOTED_SIMULATOR_UDID}"
mkdir -p .build/SpaceCursor
work=$(mktemp -d "$PWD/.build/SpaceCursor/run.XXXXXX")
app="$work/SpaceCursor.app"
mkdir -p "$app"
cat RussianExtendedKeyboard/Keyboard/KeyboardViewController.swift Tests/SpaceCursor/main.swift > "$work/main.swift"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -Onone -sdk "$sdk" -module-cache-path "$PWD/.build/BenchmarkModuleCache" \
    -target "$(uname -m)-apple-ios16.0-simulator" "$work/main.swift" -o "$app/SpaceCursor"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.keyboard.space-cursor-tests</string><key>CFBundleExecutable</key><string>SpaceCursor</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleName</key><string>SpaceCursor</string><key>UILaunchScreen</key><dict/></dict></plist>
PLIST
codesign --force --sign - "$app"
xcrun simctl install "$device" "$app"
xcrun simctl launch --terminate-running-process --console "$device" local.keyboard.space-cursor-tests > "$work/runtime.log" 2>&1
printf 'Cursor test artifacts: %s\n' "$work"
rg '^SPACE_CURSOR|Precondition failed|Fatal error' "$work/runtime.log" || true
rg -q '^SPACE_CURSOR checks=[0-9]+ passed' "$work/runtime.log"
