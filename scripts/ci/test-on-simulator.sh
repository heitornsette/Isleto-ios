#!/usr/bin/env bash
# Runs the IsletoCore tests on an iOS simulator (they also run on macOS with
# `swift test`; this checks the same code on the iOS runtime).
set -euo pipefail
cd "$(dirname "$0")/../.."
root="$PWD"
mkdir -p build/logs build/test-results

udid="$(bash scripts/ci/pick-simulator.sh)"

cd Packages/IsletoCore
# SwiftPM names the scheme "<Package>-Package" when it has several products,
# or after the single product otherwise.
schemes="$(xcodebuild -list -json 2>/dev/null | jq -r '(.workspace.schemes // .project.schemes // [])[]')"
if grep -qx 'IsletoCore-Package' <<<"$schemes"; then
  scheme='IsletoCore-Package'
else
  scheme='IsletoCore'
fi
echo "Esquema de teste: $scheme"

rm -rf "$root/build/test-results/IsletoCore.xcresult"
if ! xcodebuild test \
  -scheme "$scheme" \
  -destination "id=$udid" \
  -resultBundlePath "$root/build/test-results/IsletoCore.xcresult" \
  >"$root/build/logs/test-simulator.log" 2>&1; then
  grep -E 'error:|failed|Failing tests' "$root/build/logs/test-simulator.log" | head -n 60 || true
  tail -n 40 "$root/build/logs/test-simulator.log"
  exit 1
fi
grep -E 'Executed|TEST SUCCEEDED' "$root/build/logs/test-simulator.log" | tail -n 3
