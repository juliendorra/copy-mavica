#!/usr/bin/env bash
#
# Builds "Mavica Copy.app" without Xcode: SwiftPM release build, hand-assembled
# app bundle, codesign. Works with the Command Line Tools alone.
#
# Signing identity, in order of preference:
#   1. $CODESIGN_IDENTITY if set
#   2. "Mavica Copy Signing" (create it with Scripts/create-signing-identity.sh)
#   3. Ad-hoc signature ("-")
#
# Usage: Scripts/build-app.sh

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app_name="Mavica Copy"
bundle_id="com.juliendorra.MavicaCopy"
version="2.0.0"
build_number="3"
min_macos="13.0"

echo "==> Running MavicaCore checks"
swift run -c release MavicaChecks

echo "==> Building release binary"
swift build -c release
binary=".build/release/MavicaCopy"
[[ -x "$binary" ]] || { echo "Error: build product not found at $binary" >&2; exit 1; }

echo "==> Ensuring app icon"
if [[ ! -f "Resources/AppIcon.icns" ]]; then
  swift Scripts/make-icon.swift Resources/AppIcon.iconset
  iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
fi

echo "==> Assembling bundle"
app="dist/${app_name}.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$binary" "$app/Contents/MacOS/MavicaCopy"
cp "Resources/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>${app_name}</string>
	<key>CFBundleExecutable</key>
	<string>MavicaCopy</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>${bundle_id}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${app_name}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${version}</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
	<key>CFBundleVersion</key>
	<string>${build_number}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.photography</string>
	<key>LSMinimumSystemVersion</key>
	<string>${min_macos}</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© Julien Dorra</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>NSRemovableVolumesUsageDescription</key>
	<string>Mavica Copy reads photos from your Mavica’s floppy diskette.</string>
</dict>
</plist>
PLIST

echo 'APPL????' > "$app/Contents/PkgInfo"

echo "==> Signing"
identity="${CODESIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -q "Mavica Copy Signing"; then
    identity="Mavica Copy Signing"
  else
    identity="-"
  fi
fi

if [[ "$identity" == "-" ]]; then
  echo "    No signing identity found; using ad-hoc signature."
  echo "    Run Scripts/create-signing-identity.sh once to create a self-signed identity."
else
  echo "    Using identity: $identity"
fi

codesign --force --sign "$identity" \
  --identifier "$bundle_id" \
  --options runtime \
  "$app"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$app"

echo ""
echo "Built: $app"
codesign --display --verbose=2 "$app" 2>&1 | grep -E '^(Identifier|Authority|Signature|TeamIdentifier)' || true
