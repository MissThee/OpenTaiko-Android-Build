#!/usr/bin/env bash
# build-ios.sh - Build the OpenTaiko iOS IPA on macOS / a CI runner.
#
# Wraps OpenTaiko.iOS/scripts/deploy.sh (which downloads/builds the native
# dependencies, builds a Release ios-arm64 app and packages it as an unsigned
# .ipa + dSYM zip) and copies the artifacts to stable paths for CI upload.
#
# Output (stable paths for upload): OpenTaiko.iOS.ipa, OpenTaiko.iOS.dSYM.zip
# The IPA is built with an iOS 14 deployment target, so it runs on iOS 14+.
set -euo pipefail
cd "$(dirname "$0")"

MIN_IOS="14.0"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[build-ios] ERROR: building an iOS IPA requires macOS with Xcode command line tools." >&2
  exit 1
fi

echo "[build-ios] Verifying iOS ${MIN_IOS} deployment target..."
csproj_target=$(sed -n 's/.*<SupportedOSPlatformVersion>\([^<]*\)<\/SupportedOSPlatformVersion>.*/\1/p' \
  OpenTaiko.iOS/OpenTaiko.iOS.csproj | head -1)
plist_target=$(awk '/<key>MinimumOSVersion<\/key>/ {
  getline
  if (match($0, /<string>[^<]*<\/string>/)) { print substr($0, RSTART+8, RLENGTH-17); exit }
}' OpenTaiko.iOS/Info.plist)

if [[ "$csproj_target" != "$MIN_IOS" || "$plist_target" != "$MIN_IOS" ]]; then
  echo "[build-ios] ERROR: iOS deployment target must be ${MIN_IOS} in both" \
       "OpenTaiko.iOS.csproj (found '${csproj_target}') and Info.plist (found '${plist_target}')." >&2
  exit 1
fi

echo "[build-ios] Building unsigned Release IPA (iOS ${MIN_IOS}+)..."
bash OpenTaiko.iOS/scripts/deploy.sh ipa \
  --clean-build \
  --sign none \
  --output "$PWD/OpenTaiko.iOS.ipa"

echo "[build-ios] Done: $PWD/OpenTaiko.iOS.ipa"
