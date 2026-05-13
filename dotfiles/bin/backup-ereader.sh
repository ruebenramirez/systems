#!/usr/bin/env bash

# Script to sync Kobo eReader content with laptop and auto-unmount
# Created: May 11, 2025

# Define paths
KOBO_MOUNT_PATH="/run/media/rramirez/KOBOeReader"
LOCAL_EBOOKS_PATH="$HOME/ebooks"
KOBO_EBOOKS_PATH="$KOBO_MOUNT_PATH/ebooks"
KOBO_KOREADER_PATH="$KOBO_MOUNT_PATH/.adds/koreader"
LOCAL_KOREADER_PATH="$HOME/.config/koreader"

# Function to display error messages and exit
error_exit() {
    echo "ERROR: $1" >&2
    exit 1
}

# Check if udiskie is installed
if ! command -v udiskie &> /dev/null; then
    error_exit "udiskie is not installed. Please install it first."
fi

echo "=== Kobo Sync Script ==="
echo "Starting sync process..."

# Check if Kobo is already mounted
KOBO_WAS_ALREADY_MOUNTED=false
if [ -d "$KOBO_MOUNT_PATH" ]; then
    echo "Kobo already mounted at $KOBO_MOUNT_PATH"
    KOBO_WAS_ALREADY_MOUNTED=true
else
    echo "Attempting to mount Kobo using udiskie..."
    udiskie-mount -a

    # Wait a bit for the mount to complete
    sleep 3

    # Check if mount was successful
    if [ ! -d "$KOBO_MOUNT_PATH" ]; then
        error_exit "Failed to mount Kobo. Please check if it's connected properly."
    fi
    echo "Kobo successfully mounted at $KOBO_MOUNT_PATH"
fi

# Create local directories if they don't exist
mkdir -p "$LOCAL_EBOOKS_PATH"
mkdir -p "$LOCAL_KOREADER_PATH"

# Sync ebooks directory (laptop->Kobo)
echo "Syncing ebooks from (laptop->Kobo)..."
if [ -d "$KOBO_EBOOKS_PATH" ]; then
    # Note: excluding the `--delete` flag to not overwrite ereader data
    # Replaced -a with -rtv and --modify-window=2 for FAT32 compatibility
    rsync -rtvu --modify-window=2 --progress --exclude='.git' "$LOCAL_EBOOKS_PATH/" "$KOBO_EBOOKS_PATH/"
    echo "Ebooks sync (laptop->Kobo) completed."
else
    echo "Warning: Ebooks directory not found on Kobo. No ebooks synced."
fi

# Sync ebooks directory (Kobo->laptop)
echo "Syncing ebooks (Kobo->laptop)..."
if [ -d "$KOBO_EBOOKS_PATH" ]; then
    # Replaced -a with -rtv and --modify-window=2 for FAT32 compatibility
    rsync -rtvu --delete --modify-window=2 --progress --exclude='.git' "$KOBO_EBOOKS_PATH/" "$LOCAL_EBOOKS_PATH/"
    echo "Ebooks sync (Kobo->laptop) completed."
else
    echo "Warning: Ebooks directory not found on Kobo. No ebooks synced."
fi

# # Sync KOReader installation (Kobo->laptop)
# echo "Backing up KOReader installation (Kobo->laptop)..."
# if [ -d "$KOBO_KOREADER_PATH" ]; then
#     # Replaced -a with -rtv and --modify-window=2 for FAT32 compatibility
#     rsync -rtvu --delete --modify-window=2 --progress "$KOBO_KOREADER_PATH/" "$LOCAL_KOREADER_PATH/"
#     echo "KOReader backup (Kobo->laptop) completed."
# else
#     echo "Warning: KOReader directory not found on Kobo. No KOReader backup created."
# fi

echo "All sync operations completed successfully!"

# Unmount the Kobo if we mounted it (not if it was already mounted)
if [ "$KOBO_WAS_ALREADY_MOUNTED" = false ]; then
    echo "Unmounting Kobo eReader..."
    if udiskie-umount "$KOBO_MOUNT_PATH"; then
        echo "Kobo successfully unmounted."
    else
        echo "Warning: Failed to unmount Kobo. You may need to unmount it manually."
    fi
else
    echo "Kobo was already mounted before running this script. Not unmounting automatically."
    echo "To unmount manually, run: udiskie-umount $KOBO_MOUNT_PATH"
fi

exit 0
