#!/bin/bash
# Run against a booted iOS simulator. Optional second argument is a baseline source file.
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/../.." && pwd)
device="${1:?Usage: run.sh SIMULATOR_UDID [KeyboardViewController.swift]}"
source_file="${2:-$project_dir/RussianExtendedKeyboard/Keyboard/KeyboardViewController.swift}"
samples="${3:-1}"
if ! [[ "$samples" =~ ^[1-9][0-9]*$ ]]; then
    echo "Sample count must be a positive integer" >&2
    exit 2
fi
work=$(mktemp -d /tmp/keyboard-startup.XXXXXX)
app="$work/Benchmark.app"
mkdir -p "$app"
# A single file lets the fixture exercise private button callbacks without exposing production APIs.
cat "$source_file" "$project_dir/Tests/KeyboardStartup/main.swift" > "$work/main.swift"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -O -sdk "$sdk" -module-cache-path "$project_dir/.build/BenchmarkModuleCache" \
    -target "$(uname -m)-apple-ios16.0-simulator" "$work/main.swift" -o "$app/Benchmark"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.keyboard.startup-benchmark</string><key>CFBundleExecutable</key><string>Benchmark</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleName</key><string>Benchmark</string><key>UILaunchScreen</key><dict/></dict></plist>
PLIST
codesign --force --sign - "$app"
xcrun simctl install "$device" "$app"
echo "Benchmark artifacts: $work"
for ((sample = 1; sample <= samples; sample++)); do
    log="$work/sample-$sample.log"
    xcrun simctl launch --console "$device" local.keyboard.startup-benchmark > "$log" 2>&1
    rg '^(BENCHMARK|PHASES|PREVIEW)|error:|Precondition failed|Fatal error' "$log" || true
    # simctl can exit successfully even when a precondition kills the app.
    rg -q 'checks=passed' "$log"
done
