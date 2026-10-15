#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p apple-evidence
git rev-parse HEAD > apple-evidence/source-sha.txt
xcodebuild -version | tee apple-evidence/xcode-version.txt
xcrun --sdk iphonesimulator --show-sdk-version | tee apple-evidence/sdk-version.txt
shasum -a 256 Apple/AEGISLocal/AEGISLocalApp.swift Apple/AEGISLocal.xcodeproj/project.pbxproj > apple-evidence/source.sha256
xcodebuild -list -json -project Apple/AEGISLocal.xcodeproj > apple-evidence/project.json
xcodebuild build \
  -project Apple/AEGISLocal.xcodeproj \
  -scheme AEGISLocal \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath apple-build \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee apple-evidence/build.log

xcrun simctl list devices available --json > apple-evidence/devices.json
sim_id=$(python3 - <<'PY'
import json, re
devices=json.load(open('apple-evidence/devices.json'))['devices']
for runtime, rows in sorted(devices.items(), reverse=True):
    match=re.search(r'\.iOS-(\d+)',runtime)
    if match and int(match[1])>=26:
        for d in rows:
            if d.get('isAvailable') and d['name'].startswith('iPhone'):
                print(d['udid'])
                raise SystemExit(0)
raise SystemExit('No available iPhone simulator runtime >= iOS 26')
PY
)
printf '%s\n' "$sim_id" > apple-evidence/simulator-uuid.txt
state=$(xcrun simctl list devices --json | python3 -c 'import sys,json; rows=json.load(sys.stdin)["devices"]; print(next(d["state"] for a in rows.values() for d in a if d["udid"]==sys.argv[1]))' "$sim_id")
if [ "$state" != Booted ]; then xcrun simctl boot "$sim_id"; fi
xcrun simctl bootstatus "$sim_id" -b
xcrun simctl install "$sim_id" apple-build/Build/Products/Debug-iphonesimulator/AEGISLocal.app
xcrun simctl launch "$sim_id" org.aegis.localdesk | tee apple-evidence/launch.log
sleep 3
xcrun simctl io "$sim_id" screenshot apple-evidence/launch.png
printf '%s\n' 'BUILD_AND_SIMULATOR_LAUNCH_PASS; FOUNDATION_MODEL_INFERENCE_NOT_TESTED' > apple-evidence/result.txt
