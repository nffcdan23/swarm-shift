#!/bin/zsh
# Export, build, sign and install SWARM//SHIFT on a connected iPhone for
# internal testing. Nothing here talks to App Store Connect.
#
#   tools/ios_deploy.sh              export + build + install + launch
#   tools/ios_deploy.sh --check      same, then run the on-device self-test and print its report
#   tools/ios_deploy.sh --no-launch  install only
#
# Requirements: Godot 4.7.2 with iOS export templates, Xcode signed in to the
# team named in export_presets.cfg, and an iPhone that is connected, trusted,
# unlocked and has Developer Mode switched on.
#
# Signing uses whatever development certificate and provisioning profile Xcode
# already holds for that team. Add ALLOW_PROVISIONING=1 to let xcodebuild
# create or refresh them on your Apple developer account when needed.

set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
MODE="${1:-}"
OUT="$ROOT/build/ios"
DERIVED="$ROOT/build/ios-derived"
BUNDLE_ID=$(sed -n 's/^application\/bundle_identifier="\(.*\)"$/\1/p' export_presets.cfg | head -1)

DEVICE=$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && /connected|available/ {for (i = 1; i <= NF; i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/) print $i}' | head -1)
if [[ -z "$DEVICE" ]]; then
  echo "No connected iPhone found. Plug it in, unlock it and tap Trust."
  exit 1
fi
echo "Device:    $DEVICE"
echo "Bundle ID: $BUNDLE_ID"

echo "1/4  Exporting the Xcode project from Godot..."
mkdir -p "$OUT"
touch "$ROOT/build/.gdignore"
godot --headless --path "$ROOT" --export-debug "iOS" "$OUT/SwarmShift.ipa" > "$ROOT/build/export.log" 2>&1 || { tail -20 "$ROOT/build/export.log"; exit 1; }

echo "2/4  Building and signing..."
EXTRA=()
[[ -n "$ALLOW_PROVISIONING" ]] && EXTRA+=(-allowProvisioningUpdates)
if ! xcodebuild -project "$OUT/SwarmShift.xcodeproj" -scheme SwarmShift -configuration Debug \
    -destination "id=$DEVICE" -derivedDataPath "$DERIVED" $EXTRA build > "$ROOT/build/xcodebuild.log" 2>&1; then
  grep -E "error:|No profiles|requires a provisioning" "$ROOT/build/xcodebuild.log" | head -10
  echo "Build failed - full log: build/xcodebuild.log"
  echo "If this is a signing error, open build/ios/SwarmShift.xcodeproj in Xcode once, or re-run with ALLOW_PROVISIONING=1."
  exit 1
fi
APP="$DERIVED/Build/Products/Debug-iphoneos/SwarmShift.app"

echo "3/4  Installing (existing save data on the phone is kept)..."
xcrun devicectl device install app --device "$DEVICE" "$APP" > "$ROOT/build/install.log" 2>&1 || { tail -15 "$ROOT/build/install.log"; exit 1; }

case "$MODE" in
  --no-launch)
    echo "4/4  Installed. Tap the Swarm Shift icon to play."
    ;;
  --check)
    echo "4/4  Running the on-device self-test. Leave the phone unlocked and untouched for 45 seconds..."
    REPORT="$ROOT/build/device_check.txt"
    rm -f "$REPORT"
    xcrun devicectl device process launch --console --terminate-existing --device "$DEVICE" "$BUNDLE_ID" -- --device-check > "$ROOT/build/launch.log" 2>&1 &
    LAUNCH=$!
    sleep 45
    # The engine's own output is not forwarded over the device link, so read
    # the report file the test writes; stopping devicectl closes the app.
    xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
      --source Documents/device_check.txt --destination "$REPORT" > /dev/null 2>&1 || true
    kill $LAUNCH 2>/dev/null || true
    if [[ -f "$REPORT" ]]; then
      cat "$REPORT"
    else
      grep -q "Locked" "$ROOT/build/launch.log" && echo "The phone was locked, so the test could not start."
      echo "No report was produced - the test was interrupted or did not finish. Try again with the phone left alone."
      exit 1
    fi
    ;;
  *)
    echo "4/4  Launching..."
    xcrun devicectl device process launch --terminate-existing --device "$DEVICE" "$BUNDLE_ID" > "$ROOT/build/launch.log" 2>&1 \
      || { grep -q "Locked" "$ROOT/build/launch.log" && echo "The phone is locked - unlock it and tap the Swarm Shift icon." || tail -8 "$ROOT/build/launch.log"; }
    ;;
esac
