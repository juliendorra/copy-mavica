# copy-mavica

Copy and rename photos from a Sony Mavica floppy disk camera, with proper date handling on macOS.

## What it does

The Mavica FD5 and FD7 cameras store JPEGs with generic filenames.

`copy-mavica.sh` copies them to a destination folder, renaming each file based on its modified timestamp:

```
MVC-001.JPG  →  MAVICA-2025-07-14-16-32-05.JPG
MVC-002.JPG  →  MAVICA-2025-07-14-16-33-12.JPG
```

It also fixes the macOS creation date (which the camera sets to epoch/1970) so that Finder, Photos, and iCloud sort files correctly.

## Mac App

A macOS app built with [Platypus](https://sveinbjorn.org/platypus) is included as `Mavica Copy App.zip`. It wraps `copy-mavica.sh` in a native GUI so you can run it without a terminal. The Platypus profile (`Mavica Copy.platypus`) is also included for customization.

<img width="146" height="150" alt="Capture d’écran 2026-03-06 à 12 23 34" src="https://github.com/user-attachments/assets/2467af13-9e28-45eb-95ae-eb562c43cf1d" />

### Using the Mac app

Insert the disk first. The disk should be named MY_PHOTO (if you formatted it in the Mavica, it is already named that)

Open the app, it will detect the disk and copy the photos to a Mavica Photos at the root of your iCloud Drive folder.

<img width="169" height="176" alt="Capture d’écran 2026-03-06 à 12 07 15" src="https://github.com/user-attachments/assets/05562c93-a08f-41a0-8b49-4d6b7c6e66ce" />

## Scripts

### `copy-mavica.sh`

The main script. Copies all JPG/JPEG files from a source directory, renames them by timestamp, and fixes creation dates.

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


## Requirements

- macOS (primary target)
- `SetFile` — part of Xcode Command Line Tools (`xcode-select --install`)
- Optional: `exiftool` — used as a fallback on non-macOS systems
