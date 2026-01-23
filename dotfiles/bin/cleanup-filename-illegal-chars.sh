#!/usr/bin/env bash

# --- Usage Check ---
if [ -z "$1" ]; then
    echo "Usage: $0 <target_directory> [--apply]"
    echo "Example: $0 ./my_notes --apply"
    exit 1
fi

TARGET_DIR="$1"
APPLY_CHANGES=false

# Check if the second argument is --apply
if [[ "$2" == "--apply" ]]; then
    APPLY_CHANGES=true
fi

# Check if directory exists
if [ ! -d "$TARGET_DIR" ]; then
    echo "Error: Directory '$TARGET_DIR' does not exist."
    exit 1
fi

# --- Execution ---
if [ "$APPLY_CHANGES" = false ]; then
    echo "=== DRY RUN MODE: No files will be changed ==="
    echo "=== Run with: $0 \"$TARGET_DIR\" --apply to execute ==="
else
    echo "=== LIVE MODE: Renaming files in $TARGET_DIR... ==="
fi

echo "------------------------------------------------"

# Use depth-first search so we don't rename a parent folder before its children
find "$TARGET_DIR" -depth -name "*[|*:<>?\"\\\]*" | while read -r OLD_PATH; do
    DIR=$(dirname "$OLD_PATH")
    OLD_NAME=$(basename "$OLD_PATH")

    # 1. Delete illegal characters: | * : < > ? " \
    # 2. Replace double spaces with a single space
    # 3. Trim leading/trailing whitespace from the filename
    NEW_NAME=$(echo "$OLD_NAME" | tr -d '|*:<>?"\\' | sed 's/  */ /g' | sed 's/^ //;s/ $//')

    NEW_PATH="$DIR/$NEW_NAME"

    if [ "$OLD_PATH" != "$NEW_PATH" ]; then
        if [ "$APPLY_CHANGES" = true ]; then
            echo "Renaming: '$OLD_NAME' -> '$NEW_NAME'"
            mv -n "$OLD_PATH" "$NEW_PATH"
        else
            echo "[DRY RUN] Would rename: '$OLD_NAME' -> '$NEW_NAME'"
        fi
    fi
done

echo "------------------------------------------------"
echo "Operation complete."
