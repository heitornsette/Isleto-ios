#!/usr/bin/env bash
# Builds the app for the simulator, opens it in a few states and saves
# screenshots to build/screenshots, so the interface can be seen without a device.
set -euo pipefail
cd "$(dirname "$0")/../.."
out="build/screenshots"
derived="build/SimDerivedData"
log="build/logs/sim-build.log"
mkdir -p "$out" build/logs
: >"$log"

udid="$(bash scripts/ci/pick-simulator.sh)"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null

build() {
  xcodebuild build \
    -project Isleto.xcodeproj \
    -scheme Isleto \
    -configuration Debug \
    -destination "id=$udid" \
    -derivedDataPath "$derived" \
    "$@" >>"$log" 2>&1
}

# Ad-hoc signing first: on the simulator it keeps the entitlements, so the App
# Group behaves like on a device. If Xcode refuses it, build without signing; then
# the App Group may show as unavailable in the screenshots ONLY.
if build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= CODE_SIGNING_REQUIRED=NO; then
  mode="simulador, assinatura ad-hoc (entitlements aplicados)"
else
  echo "Build ad-hoc falhou; tentando sem assinatura." | tee -a "$log"
  if ! build CODE_SIGNING_ALLOWED=NO; then
    grep -E 'error:' "$log" | head -n 60 || true
    tail -n 40 "$log"
    exit 1
  fi
  mode="simulador, sem assinatura (App Group pode falhar só aqui)"
fi
echo "$mode" | tee "$out/modo-de-build.txt"

app="$derived/Build/Products/Debug-iphonesimulator/Isleto.app"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
xcrun simctl install "$udid" "$app"
xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 || true

shot() {
  xcrun simctl io "$udid" screenshot "$out/$1.png" >/dev/null
  echo "captura: $1.png"
}
launch() {
  xcrun simctl terminate "$udid" "$bundle_id" 2>/dev/null || true
  xcrun simctl launch "$udid" "$bundle_id" "$@" >/dev/null
  sleep 6
}

launch
shot 01-hoje-vazio
launch --demo-seed
shot 02-hoje-com-dados
launch --demo-scroll habits
shot 03-habitos
launch --demo-focus
shot 04-foco-ativo
# Leaving the app shows the Live Activity in the Dynamic Island (Pro simulators).
xcrun simctl launch "$udid" com.apple.Preferences >/dev/null || true
sleep 4
shot 05-dynamic-island
launch --demo-diagnostics
shot 06-diagnostico-e-widget
xcrun simctl ui "$udid" appearance dark || true
launch
shot 07-hoje-escuro
