#!/usr/bin/env bash
# Builds build/Isleto.ipa for the iPhone without a real signature.
#
# Without signing, Xcode drops the entitlements (App Group). So each binary gets a
# fake signature with ldid that carries its entitlements: Sideloadly reads them to
# know which capabilities to request when it signs with the free Apple ID.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/logs

archive="build/Isleto.xcarchive"
commit="${GITHUB_SHA:-local}"
commit="${commit:0:7}"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2"; }

rm -rf "$archive"
if ! xcodebuild archive \
  -project Isleto.xcodeproj \
  -scheme Isleto \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive" \
  -derivedDataPath build/DerivedData \
  ISLETO_COMMIT="$commit" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  >build/logs/archive.log 2>&1; then
  grep -E 'error:' build/logs/archive.log | head -n 60 || true
  tail -n 40 build/logs/archive.log
  exit 1
fi

app="$archive/Products/Applications/Isleto.app"
appex="$app/PlugIns/IsletoWidgets.appex"
[ -d "$app" ] || { echo "Isleto.app não está no archive." >&2; exit 1; }
[ -d "$appex" ] || { echo "IsletoWidgets.appex não foi embutida no app." >&2; exit 1; }

group="$(plist 'com.apple.security.application-groups:0' App/Isleto.entitlements)"
for bundle in "$app" "$appex"; do
  info_group="$(plist IsletoAppGroup "$bundle/Info.plist")"
  if [ "$info_group" != "$group" ]; then
    echo "App Group divergente em $(basename "$bundle"): Info.plist=$info_group, entitlements=$group" >&2
    exit 1
  fi
done

# Inner code first, the app last.
if [ -d "$app/Frameworks" ]; then
  find "$app/Frameworks" -mindepth 1 -maxdepth 1 \( -name '*.dylib' -o -name '*.framework' \) | while read -r item; do
    if [ -d "$item" ]; then item="$item/$(plist CFBundleExecutable "$item/Info.plist")"; fi
    ldid -S "$item"
  done
fi
appex_bin="$appex/$(plist CFBundleExecutable "$appex/Info.plist")"
app_bin="$app/$(plist CFBundleExecutable "$app/Info.plist")"
# No space after -S: ldid takes the file name glued to the flag.
ldid -SWidgets/IsletoWidgets.entitlements "$appex_bin"
ldid -SApp/Isleto.entitlements "$app_bin"

: >build/logs/entitlements.txt
for bin in "$appex_bin" "$app_bin"; do
  {
    echo "== $(basename "$bin")"
    ldid -e "$bin"
  } >>build/logs/entitlements.txt
  if ! ldid -e "$bin" | grep -q "$group"; then
    echo "Entitlements sem $group em $(basename "$bin")." >&2
    cat build/logs/entitlements.txt >&2
    exit 1
  fi
done
cat build/logs/entitlements.txt

rm -rf build/ipa build/Isleto.ipa
mkdir -p build/ipa/Payload
ditto "$app" build/ipa/Payload/Isleto.app
(cd build/ipa && zip -qry ../Isleto.ipa Payload)
echo "IPA: build/Isleto.ipa ($(du -h build/Isleto.ipa | cut -f1)), commit $commit"
