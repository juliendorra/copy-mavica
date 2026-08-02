# copy-mavica

Copy and rename photos from a Sony Mavica floppy disk camera, with proper date handling on macOS.

## What it does

The Mavica FD5 and FD7 cameras store JPEGs with generic filenames on 3.5" floppy diskettes.

This project copies them to a destination folder, renaming each file based on its modified timestamp:

```
MVC-001.JPG  →  MAVICA-2025-07-14-16-32-05.JPG
MVC-002.JPG  →  MAVICA-2025-07-14-16-33-12.JPG
```

It also fixes the macOS creation date (which the camera sets to epoch/1970) so that Finder, Photos, and iCloud sort files correctly.

## Mavica Copy — native Mac app

A real SwiftUI macOS app, built **without Xcode**: only the Command Line Tools, SwiftPM, and a hand-assembled app bundle (the same pure-Swift technique as the Padipop iPod/iPad project).

- Detects a mounted Mavica floppy (`MY_PHOTO`) automatically, live on mount/eject.
- Copies all JPEGs (skipping `._` AppleDouble junk), renamed to `MAVICA-YYYY-MM-DD-HH-MM-SS.JPG`, with `--2`, `--3`… on collisions.
- Sets each copy's creation date to the photo's modification date — no `SetFile` needed.
- Destination defaults to `iCloud Drive/Mavica Photos`; any folder can be chosen and is remembered.
- Progress bar, activity log, Show in Finder, and one-click Eject Floppy when done.

### Build

```bash
Scripts/build-app.sh        # runs checks, builds, assembles and signs dist/Mavica Copy.app
```

Requirements: macOS 13+, Command Line Tools (`xcode-select --install`). No Xcode, no Apple Developer account.

### Signing

By default the app is ad-hoc signed, which runs fine on the Mac that built it.
For a stable self-signed identity (survives rebuilds, keeps TCC permission grants):

```bash
Scripts/create-signing-identity.sh   # run interactively once; approve the keychain dialogs
Scripts/build-app.sh                 # now signs with "Mavica Copy Signing"
```

### Project layout

```
Package.swift             SwiftPM manifest (no Xcode project)
Sources/MavicaCore/       portable engine: scan, rename, collision, date fixing
                          (shared unchanged by the Mac and iOS apps)
Sources/MavicaCopy/       SwiftUI Mac app
Sources/MavicaCopyMobile/ SwiftUI iOS app
Checks/                   plain-executable tests: swift run MavicaChecks
                          (XCTest is not shipped with the Command Line Tools)
Scripts/build-app.sh      Mac: build + bundle + codesign
Scripts/build-ios-ipa.sh  iOS: xcodegen + xcodebuild + unsigned IPA (CI)
Scripts/make-icon.swift   draws the floppy app icon, rendered to .icns via iconutil
Scripts/make-ios-icon.swift  same artwork, full-bleed and opaque for iOS
project.yml               XcodeGen spec for the iOS app (project is generated, not committed)
Resources/AppIcon.icns    generated app icon
```

## Mavica Copy — iOS app

The same app for iPhone and iPad, sharing `MavicaCore` untouched. Plug the floppy drive into the device with a USB adapter — the diskette shows up in the Files app as `MY_PHOTO`.

Because iOS has no `/Volumes` and no Finder, the flow adapts:

- **Source**: pick the `MY_PHOTO` diskette (or any folder) in the Files picker. The choice is remembered with a security-scoped bookmark, so re-plugging the drive reconnects automatically when the app returns to the foreground.
- **Destination**: pick `Mavica Photos` in iCloud Drive — the very same folder the Mac app writes to, so both devices import into one place. Also remembered across launches.
- Same renaming (`MAVICA-YYYY-MM-DD-HH-MM-SS.JPG`, `--2` on collisions), same creation-date fix, same activity log.

### Build (GitHub Actions — the "no Xcode" way, like Padipop)

The iOS SDK is not part of the Command Line Tools, so the app is built by CI, not locally:

1. Run the **Build iOS IPA** workflow (Actions tab → *Build iOS IPA* → *Run workflow*).
2. Download the `MavicaCopy-unsigned.ipa` artifact.
3. Sideload it with [Sideloadly](https://sideloadly.io/) using your own (free) Apple ID.

The pipeline is `xcodegen` (from `project.yml`) → unsigned `xcodebuild` → `ditto`-assembled IPA; no `.xcodeproj` is ever committed. On a Mac with full Xcode installed, `Scripts/build-ios-ipa.sh` runs the same pipeline locally.

### TestFlight

The **Release to TestFlight** workflow archives, signs, and uploads to App Store Connect using Xcode cloud-managed signing — no certificate or provisioning profile is ever stored in the repo or in GitHub. It needs a paid Apple Developer membership plus four GitHub Actions secrets:

| Secret | Value |
|---|---|
| `ASC_API_KEY_ID` | App Store Connect API key ID (**Admin** role — cloud signing must be able to create the Apple Distribution certificate) |
| `ASC_API_ISSUER_ID` | The key's issuer ID |
| `ASC_API_PRIVATE_KEY` | Contents of the downloaded `.p8` file |
| `APPLE_TEAM_ID` | 10-character team ID |

One-time setup in App Store Connect: create the app record with bundle ID `com.juliendorra.MavicaCopy`, then run the workflow; the processed build appears under TestFlight, where you add yourself as an internal tester.

## Legacy: shell script and Platypus app

The original `copy-mavica.sh` and the [Platypus](https://sveinbjorn.org/platypus)-wrapped app (`Mavica Copy App.zip`, profile `Mavica Copy.platypus`) are kept for reference.

### `copy-mavica.sh`

Copies all JPG/JPEG files from a source directory, renames them by timestamp, and fixes creation dates.

**Usage:**

```bash
# Auto-detect Mavica disk at /Volumes/MY_PHOTO, copy to current directory
./copy-mavica.sh

# Copy to a specific folder
./copy-mavica.sh ~/Pictures/Mavica

# Specify a custom source path
./copy-mavica.sh --source /path/to/photos ~/Pictures/Mavica

# Copy directly to iCloud Drive (default subfolder: "Mavica Photos")
./copy-mavica.sh --icloud

# Copy to a custom iCloud subfolder
./copy-mavica.sh --icloud "My Camera Roll"

# Use an iCloud path as the source
./copy-mavica.sh --source-icloud "Some/Folder"
```

**Features:**
- Auto-detects the Mavica disk at common mount points (`/Volumes/MY_PHOTO`, `/media/$USER/MY_PHOTO`, etc.)
- Handles filename collisions by appending `--2`, `--3`, etc.
- Sets creation date via `SetFile` (macOS) or `exiftool` (fallback)
- Normalizes Finder-pasted iCloud paths (fixes tilde encoding, duplicate slashes)

### `fix-creation-date.sh`

A standalone utility to fix null creation dates (Jan 1, 1970) on existing Mavica JPEGs. Useful if you already copied files without fixing dates.

```bash
# Fix files in a directory
./fix-creation-date.sh ~/Pictures/Mavica

# Fix files in current directory
./fix-creation-date.sh .
```

Requires `SetFile` (included with Xcode Command Line Tools).
