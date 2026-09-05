#!/bin/bash
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/../../.." && pwd)
device="${1:?Usage: record.sh SIMULATOR_UDID [OUTPUT_DIRECTORY]}"
output="${2:-$project_dir/.build/StartupProfile}"
mkdir -p "$output/StartupProfile.app"
app="$output/StartupProfile.app"
sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator swiftc -O -g -whole-module-optimization -c -sdk "$sdk" \
    -module-cache-path "$project_dir/.build/BenchmarkModuleCache" \
    -target "$(uname -m)-apple-ios16.0-simulator" \
    "$project_dir/RussianExtendedKeyboard/Keyboard/KeyboardViewController.swift" \
    "$project_dir/Tests/KeyboardStartup/Profiling/main.swift" -o "$output/StartupProfile.o"
xcrun --sdk iphonesimulator swiftc -g -sdk "$sdk" \
    -target "$(uname -m)-apple-ios16.0-simulator" \
    "$output/StartupProfile.o" -o "$app/StartupProfile"
xcrun dsymutil "$app/StartupProfile" -o "$output/StartupProfile.app.dSYM"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.keyboard.startupprofile</string><key>CFBundleExecutable</key><string>StartupProfile</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleName</key><string>StartupProfile</string><key>UILaunchScreen</key><dict/></dict></plist>
PLIST
codesign --force --sign - "$app"
xcrun simctl install "$device" "$app"
data=$(xcrun simctl get_app_container "$device" local.keyboard.startupprofile data)
# This marker belongs only to the profiling harness.
rm -f "$data/start-profile" "$data/profile-ready"
launch=$(xcrun simctl launch --stdout="$data/profile.log" --stderr="$data/profile-stderr.log" "$device" local.keyboard.startupprofile)
pid="${launch##*: }"
[[ "$pid" =~ ^[0-9]+$ ]]
for ((attempt = 0; attempt < 300; attempt++)); do
    [[ -f "$data/profile-ready" ]] && break
    kill -0 "$pid"
    sleep 0.2
done
[[ -f "$data/profile-ready" ]] || { echo "Profiling app did not become ready" >&2; exit 1; }
sample "$pid" 12 1 -file "$output/startup.sample.txt" > "$output/sampler.log" 2>&1 &
sampler=$!
trap 'kill "$sampler" 2>/dev/null || true' EXIT
# Allow the sampler to attach while the app is still waiting; this is outside startup.
sleep 1
touch "$data/start-profile"
wait "$sampler"
trap - EXIT
cp "$data/profile.log" "$output/profile.log"
cat "$output/profile.log"
rg -q "PROFILE completed first=1 repeated=500" "$output/profile.log"
echo "Stack samples: $output/startup.sample.txt"
