#!/usr/bin/env bash

# Builds the iOS app and packages an unsigned, sideloadable IPA — the same
# no-Xcode-GUI pipeline as Padipop: xcodegen generates the project, xcodebuild
# compiles unsigned, ditto assembles the Payload zip. Sign the resulting IPA
# on your own device with Sideloadly (or any resigner).
#
# Requires a full Xcode install (iOS SDK). On a Command Line Tools-only Mac
# this script cannot run; push and use the "Build iOS IPA" GitHub Actions
# workflow instead, then download the IPA artifact.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild is unavailable (Command Line Tools only?)." >&2
  echo "Run the 'Build iOS IPA' GitHub Actions workflow instead." >&2
  exit 1
fi

: "${XCODEGEN_BIN:=xcodegen}"

app_name="MavicaCopyMobile"
bundle_id="com.juliendorra.MavicaCopy"
derived_data="$repo_root/.build/ios-derived-data"
staging="$repo_root/.build/unsigned-ipa"
ipa="$repo_root/dist/MavicaCopy-unsigned.ipa"

rm -rf "$derived_data" "$staging" "$app_name.xcodeproj"
mkdir -p "$staging/Payload" "$repo_root/dist"

# The portable core checks run everywhere the Swift toolchain does.
swift run -c release MavicaChecks

"$XCODEGEN_BIN" --spec project.yml

# Sanity-compile for the simulator SDK before the device build.
xcodebuild build \
  -project "$app_name.xcodeproj" \
  -scheme "$app_name" \
  -configuration Debug \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

xcodebuild build \
  -project "$app_name.xcodeproj" \
  -scheme "$app_name" \
  -configuration Release \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

app="$derived_data/Build/Products/Release-iphoneos/$app_name.app"
test -d "$app"
test -x "$app/$app_name"
test ! -e "$app/embedded.mobileprovision"

built_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
test "$built_bundle_id" = "$bundle_id"

architectures="$(lipo -archs "$app/$app_name")"
[[ " $architectures " == *" arm64 "* ]]

if codesign --verify "$app" >/dev/null 2>&1; then
  echo "Expected an unsigned app, but codesign verification succeeded." >&2
  exit 1
fi

ditto "$app" "$staging/Payload/$app_name.app"
(
  cd "$staging"
  ditto -c -k --sequesterRsrc --keepParent Payload "$ipa"
)

unzip -t "$ipa" >/dev/null
unzip -Z1 "$ipa" | /usr/bin/grep -Fqx "Payload/$app_name.app/Info.plist"
test -s "$ipa"

printf 'Unsigned IPA: %s\n' "$ipa"
