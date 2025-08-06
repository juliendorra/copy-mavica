#!/bin/bash

# Show help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo ""
    echo "Fix creation dates for Mavica .JPG files with null creation dates (Jan 1, 1970)"
    echo "Usage: $0 [directory]"
    echo ""
    echo "Arguments:"
    echo "  directory    Target directory to process (default: $DEFAULT_DIR)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Use default directory"
    echo "  $0 .                                 # Use current directory"
    echo "  $0 \"/Users/me/Pictures\"              # Use specific directory"
    echo ""
    exit 0
fi

# Default target directory (change this path as needed)
DEFAULT_DIR="./premier tests copie"

# Use command-line argument if provided, otherwise use default
TARGET_DIR="${1:-$DEFAULT_DIR}"

echo "Processing .JPG files in: $TARGET_DIR"

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

find "$TARGET_DIR" -name "*.JPG" | while read file; do
    creation_epoch=$(stat -f "%B" "$file")
    if [ "$creation_epoch" = "0" ]; then
        echo "Fixing: $file"
        # Get modification date in the format SetFile expects
        moddate=$(stat -f "%Sm" -t "%m/%d/%Y %H:%M:%S" "$file")
        SetFile -d "$moddate" "$file"
    fi
done

echo "Processing complete."