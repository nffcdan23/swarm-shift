#!/bin/zsh
# Builds a Release archive of SWARM//SHIFT and, on request, uploads it to App
# Store Connect for TestFlight. Nothing here publishes anything or invites
# anyone: an uploaded build goes no further than App Store Connect.
#
#   tools/ios_release.sh              export + archive + export a signed .ipa
#   tools/ios_release.sh --upload     the same, then upload the build
#
# Version and build number come from export_presets.cfg. App Store Connect
# refuses a build number it has already seen, so raise application/version
# before every upload.
#
# Signing is automatic with the team in export_presets.cfg. -allowProvisioningUpdates
# lets Xcode create the App ID and distribution profile it needs on that team,
# using the Apple account signed in to Xcode.

set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"
MODE="${1:-}"
OUT="$ROOT/build/ios-release"
ARCHIVE="$ROOT/build/SwarmShift.xcarchive"
TEAM=$(sed -n 's/^application\/app_store_team_id="\(.*\)"$/\1/p' export_presets.cfg | head -1)
BUNDLE_ID=$(sed -n 's/^application\/bundle_identifier="\(.*\)"$/\1/p' export_presets.cfg | head -1)
VERSION=$(sed -n 's/^application\/short_version="\(.*\)"$/\1/p' export_presets.cfg | head -1)
BUILD=$(sed -n 's/^application\/version="\(.*\)"$/\1/p' export_presets.cfg | head -1)
echo "SWARM//SHIFT $VERSION ($BUILD)   $BUNDLE_ID   team $TEAM"

if [[ ! -f "$ROOT/addons/admob/admob.gdextension" ]]; then
  echo "Building the AdMob bridge..."
  "$ROOT/tools/build_admob.sh"
  godot --headless --path "$ROOT" --import > "$ROOT/build/import.log" 2>&1 || true
fi

echo "1/3  Exporting the Xcode project (Release)..."
mkdir -p "$OUT"
touch "$ROOT/build/.gdignore"
godot --headless --path "$ROOT" --export-release "iOS" "$OUT/SwarmShift.ipa" > "$ROOT/build/export-release.log" 2>&1 || { tail -20 "$ROOT/build/export-release.log"; exit 1; }

echo "2/3  Archiving..."
rm -rf "$ARCHIVE"
# The project's Release configuration names an Apple Distribution certificate.
# Archiving with the development one lets Xcode's cloud signing apply
# distribution signing at export, so no private key has to live on this Mac.
if ! xcodebuild -project "$OUT/SwarmShift.xcodeproj" -scheme SwarmShift -configuration Release \
    -destination "generic/platform=iOS" -archivePath "$ARCHIVE" -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY="Apple Development" archive > "$ROOT/build/archive.log" 2>&1; then
  grep -E "error:|requires a provisioning|No Accounts|No profiles" "$ROOT/build/archive.log" | head -12
  echo "Archive failed - full log: build/archive.log"
  exit 1
fi

DESTINATION=export
[[ "$MODE" == "--upload" ]] && DESTINATION=upload
OPTIONS="$ROOT/build/ExportOptions.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>$DESTINATION</string>
	<key>teamID</key><string>$TEAM</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>testFlightInternalTestingOnly</key><true/>
</dict>
</plist>
PLIST

echo "3/3  Signing for App Store Connect ($DESTINATION)..."
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$ROOT/build/ios-ipa" -exportOptionsPlist "$OPTIONS" \
    -allowProvisioningUpdates > "$ROOT/build/export-archive.log" 2>&1; then
  grep -E "error:|Error Domain|ITMS-|No suitable application|not found" "$ROOT/build/export-archive.log" | head -16
  echo "Failed - full log: build/export-archive.log"
  exit 1
fi
tail -3 "$ROOT/build/export-archive.log"
echo "Done."
