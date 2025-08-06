#!/usr/bin/env bash
#
# copy-mavica.sh  —  Copy & rename Mavica JPEGs, with iCloud-friendly paths
#
# - Copies all JPG/JPEG from a source (default auto-detect /Volumes/MY_PHOTO).
# - Renames on the fly to: MAVICA-YYYY-MM-DD-HH-MM-SS.JPG
# - On collision appends --2, --3, ...
# - Sets creation date = modified date (macOS via SetFile; else EXIF with exiftool).
# - Accepts Finder-pasted iCloud paths and normalizes them (no escaping issues).
#
# Usage:
#   ./copy-mavica.sh [DEST_DIR]
#   ./copy-mavica.sh --source /path/to/source [DEST_DIR]
#   ./copy-mavica.sh --source-icloud "Sub/Path/Under/iCloud"
#   ./copy-mavica.sh --icloud ["Mavica Photos"]
#
# iCloud root (on disk):
#   $HOME/Library/Mobile Documents/com~apple~CloudDocs
#
set -euo pipefail

print_usage() {
  cat <<'EOF'
Copy Mavica JPEGs from a source, renaming by modified time.

USAGE:
  copy-mavica.sh [DEST_DIR]
  copy-mavica.sh --source /path/to/source [DEST_DIR]
  copy-mavica.sh --source-icloud "Sub/Path/Under/iCloud"
  copy-mavica.sh --icloud ["Mavica Photos"]

ARGS:
  DEST_DIR   Destination folder (default: .)

OPTIONS:
  --source PATH            Explicit source path (default: auto-detect common mount points)
  --source-icloud SUBPATH  Build source path under iCloud Drive root
                           ($HOME/Library/Mobile Documents/com~apple~CloudDocs/SUBPATH)
  --icloud [SUBFOLDER]     Send output to iCloud Drive (default subfolder: "Mavica Photos")
  -h, --help               Show help
EOF
}

SOURCE_PATH=""
DEST_DIR="${PWD}"
USE_ICLOUD=false
ICLOUD_SUBDIR="Mavica Photos"

# ---------- Helpers ----------

# Trim leading/trailing whitespace (incl. newlines) — bash 3.2 compatible
trim_ws() {
  local s="$1"
  # remove CR and LF
  s="${s//$'\r'/}"
  s="${s//$'\n'/}"
  # trim leading
  s="${s#"${s%%[![:space:]]*}"}"
  # trim trailing
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# Normalize common Finder/iCloud variations WITHOUT introducing backslashes
normalize_icloud_path() {
  local in_path="$1"
  # Nothing to do for empty
  [[ -z "$in_path" ]] && { printf '%s' "$in_path"; return; }

  # Trim whitespace/newlines
  local out_path
  out_path="$(trim_ws "$in_path")"

  # Fix missing tildes in the CloudDocs bundle name
  # e.g., ".../comappleCloudDocs/..." -> ".../com~apple~CloudDocs/..."
  out_path="${out_path//comappleCloudDocs/com~apple~CloudDocs}"

  # Map "$HOME/iCloud Drive/..." to on-disk CloudDocs location
  if [[ "$out_path" == "$HOME/iCloud Drive"* ]]; then
    local rest="${out_path#"$HOME/iCloud Drive"/}"
    out_path="$HOME/Library/Mobile Documents/com~apple~CloudDocs/$rest"
  fi

  # Compact any accidental duplicate slashes (except leading // for AFP, which we don't expect here)
  while [[ "$out_path" == *"//"* ]]; do
    out_path="${out_path//\/\//\/}"
  done

  printf '%s' "$out_path"
}

# Get formatted modified time for filename (YYYY-MM-DD-HH-MM-SS)
get_mtime_for_name() {
  local file="$1"
  if [[ "${OSTYPE:-}" == darwin* ]]; then
    stat -f "%Sm" -t "%Y-%m-%d-%H-%M-%S" "$file"
  else
    date -d "@$(stat -c %Y "$file")" +%Y-%m-%d-%H-%M-%S
  fi
}

# Get modified time in SetFile format (MM/DD/YYYY HH:MM:SS)
get_mtime_setfile_fmt() {
  local file="$1"
  if command -v stat >/dev/null 2>&1; then
    if [[ "${OSTYPE:-}" == darwin* ]]; then
      stat -f "%Sm" -t "%m/%d/%Y %H:%M:%S" "$file"
    else
      date -d "@$(stat -c %Y "$file")" +%m/%d/%Y\ %H:%M:%S
    fi
  else
    date +%m/%d/%Y\ %H:%M:%S
  fi
}

# ---------- Parse arguments ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -lt 2 ]] && { echo "Error: --source requires a path" >&2; exit 1; }
      SOURCE_PATH="$2"; shift 2 ;;
    --source-icloud)
      [[ $# -lt 2 ]] && { echo "Error: --source-icloud requires a subpath under iCloud Drive" >&2; exit 1; }
      ICLOUD_ROOT_DEFAULT="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
      ICLOUD_ROOT="${ICLOUD_DRIVE_DIR:-$ICLOUD_ROOT_DEFAULT}"
      [[ ! -d "$ICLOUD_ROOT" ]] && { echo "Error: iCloud Drive root not found at '$ICLOUD_ROOT'." >&2; exit 1; }
      SOURCE_PATH="$ICLOUD_ROOT/$2"; shift 2 ;;
    --icloud)
      USE_ICLOUD=true
      if [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
        ICLOUD_SUBDIR="$2"; shift 2
      else
        shift 1
      fi ;;
    -h|--help)
      print_usage; exit 0 ;;
    -*)
      echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      DEST_DIR="$1"; shift ;;
  esac
done

# Apply normalization if user pasted a Finder/iCloud path
SOURCE_PATH="$(normalize_icloud_path "$SOURCE_PATH")"
DEST_DIR="$(normalize_icloud_path "$DEST_DIR")"

# Resolve source if not provided
if [[ -z "${SOURCE_PATH}" ]]; then
  CANDIDATES=(
    "/Volumes/MY_PHOTO"
    "/media/${USER:-}/MY_PHOTO"
    "/run/media/${USER:-}/MY_PHOTO"
    "/mnt/MY_PHOTO"
  )
  for p in "${CANDIDATES[@]}"; do
    if [[ -d "$p" ]]; then SOURCE_PATH="$p"; break; fi
  done
fi

[[ -z "${SOURCE_PATH}" ]] && { echo "Error: Could not find source. Mount 'MY_PHOTO' or use --source PATH." >&2; exit 1; }

if [[ ! -d "$SOURCE_PATH" ]]; then
  echo "Error: Source path '$SOURCE_PATH' does not exist or is not a directory." >&2
  exit 1
fi

# If --icloud was requested, compute DEST_DIR to iCloud Drive
if $USE_ICLOUD; then
  ICLOUD_ROOT_DEFAULT="${HOME}/Library/Mobile Documents/com~apple~CloudDocs"
  ICLOUD_ROOT="${ICLOUD_DRIVE_DIR:-$ICLOUD_ROOT_DEFAULT}"
  [[ ! -d "$ICLOUD_ROOT" ]] && { echo "Error: iCloud Drive root not found at '$ICLOUD_ROOT'." >&2; exit 1; }
  DEST_DIR="${ICLOUD_ROOT}/${ICLOUD_SUBDIR}"
fi

# Create destination if it doesn't exist
mkdir -p "$DEST_DIR"

echo "Source:      $SOURCE_PATH"
echo "Destination: $DEST_DIR"
echo ""

# ---------- Main loop ----------
# Use find -print0 to safely handle all filenames
while IFS= read -r -d '' SRC_FILE; do
  TS="$(get_mtime_for_name "$SRC_FILE")"
  BASE="MAVICA-${TS}"
  EXT="JPG"

  DEST_PATH="${DEST_DIR}/${BASE}.${EXT}"
  n=2
  while [[ -e "$DEST_PATH" ]]; do
    DEST_PATH="${DEST_DIR}/${BASE}--${n}.${EXT}"
    ((n++))
  done

  # Preserve timestamps so mtime stays intact for SetFile/exiftool
  cp -p "$SRC_FILE" "$DEST_PATH"

  # Set filesystem creation date (macOS) or EXIF dates (fallback)
  if command -v SetFile >/dev/null 2>&1; then
    SETFILE_DATE="$(get_mtime_setfile_fmt "$SRC_FILE")"
    SetFile -d "$SETFILE_DATE" "$DEST_PATH" || true
  elif command -v exiftool >/dev/null 2>&1; then
    exiftool -overwrite_original \
      -FileCreateDate='${FileModifyDate}' \
      -CreateDate='${FileModifyDate}' \
      -DateTimeOriginal='${FileModifyDate}' \
      "$DEST_PATH" >/dev/null 2>&1 || true
  fi

  echo "Copied: '$SRC_FILE' -> '$(basename "$DEST_PATH")'"
done < <(find "$SOURCE_PATH" -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0)

echo ""
echo "Done."
