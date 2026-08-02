#!/usr/bin/env bash

# Archive, sign, and upload Mavica Copy for iOS to App Store Connect
# (TestFlight). Same cloud-managed-signing strategy as Padipop.
#
# Required environment:
#   ASC_API_KEY_ID       App Store Connect API key ID (Admin role — App Manager is
#                        not enough: cloud signing must create an Apple Distribution
#                        certificate, which only Admin may do. A lesser role still
#                        archives successfully with a development identity and then
#                        fails at exportArchive with "Cloud signing permission error".)
#   ASC_API_ISSUER_ID    App Store Connect API issuer ID
#   ASC_API_PRIVATE_KEY  Contents of the .p8 private key
#   APPLE_TEAM_ID        10-character Apple Developer team ID
#
# Signing uses Xcode cloud-managed certificates via the API key; no
# certificate or provisioning profile is stored in the repository or in
# GitHub. The key material only ever exists in RUNNER_TEMP and is removed
# on exit.

set -euo pipefail

: "${ASC_API_KEY_ID:?ASC_API_KEY_ID is required}"
: "${ASC_API_ISSUER_ID:?ASC_API_ISSUER_ID is required}"
: "${ASC_API_PRIVATE_KEY:?ASC_API_PRIVATE_KEY is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${XCODEGEN_BIN:=xcodegen}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app_name="MavicaCopyMobile"
work="${RUNNER_TEMP:-$(mktemp -d)}/mavica-release"
key_dir="$work/private_keys"
key_path="$key_dir/AuthKey_${ASC_API_KEY_ID}.p8"
archive_path="$work/$app_name.xcarchive"
export_path="$work/export"
export_options="$work/ExportOptions.plist"

cleanup() {
  rm -rf "$key_dir"
}
trap cleanup EXIT

rm -rf "$work" "$app_name.xcodeproj"
mkdir -p "$key_dir" "$export_path"
umask 077
printf '%s\n' "$ASC_API_PRIVATE_KEY" > "$key_path"

# The portable core checks run everywhere the Swift toolchain does.
swift run -c release MavicaChecks

"$XCODEGEN_BIN" --spec project.yml

xcodebuild archive \
  -project "$app_name.xcodeproj" \
  -scheme "$app_name" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_API_ISSUER_ID" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic

cat > "$export_options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>upload</string>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>uploadSymbols</key>
  <true/>
  <key>manageAppVersionAndBuildNumber</key>
  <false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_path" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_API_ISSUER_ID"

echo "Upload to App Store Connect completed. Check the build's processing state in TestFlight."
