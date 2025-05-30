#!/usr/bin/env bash

# Ref: https://gist.github.com/mx00s/ea2462a3fe6fdaa65692fe7ee824de3e
# NixOS install script synthesized from:
#
#   - Erase Your Darlings (https://grahamc.com/blog/erase-your-darlings)
#   - ZFS Datasets for NixOS (https://grahamc.com/blog/nixos-on-zfs)
#   - NixOS Manual (https://nixos.org/nixos/manual/)
#
# It expects the name of the block device (e.g. 'sda') to partition
# and install NixOS on.
#
# Example: `setup.sh sda`
#

set -euo pipefail

################################################################################

export COLOR_RESET="\033[0m"
export RED_BG="\033[41m"
export BLUE_BG="\033[44m"

# If disk provisioning goes wrong
function cleanup {
  set +e
  umount /mnt/boot
  sleep 5
  zfs destroy -r zroot
  sleep 5
  umount /zroot
  sleep 5
  zpool destroy zroot
}

function err {
    echo -e "${RED_BG}$1${COLOR_RESET}"
}

function info {
    echo -e "${BLUE_BG}$1${COLOR_RESET}"
}

################################################################################

# Check if disk is an SSD
function is_ssd {
    local disk_name=$1
    # Check if rotational is 0 (SSD) or 1 (HDD)
    if [[ -f "/sys/block/${disk_name}/queue/rotational" ]]; then
        local rotational=$(cat "/sys/block/${disk_name}/queue/rotational")
        if [[ "$rotational" == "0" ]]; then
            return 0  # It's an SSD
        fi
    fi
    return 1  # It's not an SSD or we couldn't determine
}

################################################################################

export DISK=$1

if ! [[ -v DISK ]]; then
    err "Missing argument. Expected block device name, e.g. 'sda'"
    exit 1
fi

export DISK_PATH="/dev/${DISK}"

if ! [[ -b "$DISK_PATH" ]]; then
    err "Invalid argument: '${DISK_PATH}' is not a block special file"
    exit 1
fi

if [[ "$EUID" > 0 ]]; then
    err "Must run as root"
    exit 1
fi

export ZFS_POOL="zroot"

# ephemeral datasets
export ZFS_LOCAL="${ZFS_POOL}/local"
export ZFS_DS_ROOT="${ZFS_LOCAL}/root"
export ZFS_DS_NIX="${ZFS_LOCAL}/nix"

# persistent datasets
export ZFS_SAFE="${ZFS_POOL}/safe"
export ZFS_DS_HOME="${ZFS_SAFE}/home"
export ZFS_DS_PERSIST="${ZFS_SAFE}/persist"

export ZFS_BLANK_SNAPSHOT="${ZFS_DS_ROOT}@blank"

################################################################################

info "Running the UEFI (GPT) partitioning and formatting directions from the NixOS manual ..."
parted "$DISK_PATH" -- mklabel gpt
parted "$DISK_PATH" -- mkpart primary 512MiB -32GB
parted "$DISK_PATH" -- mkpart swap linux-swap -32GB 100%
parted "$DISK_PATH" -- mkpart ESP fat32 1MiB 512MiB
parted "$DISK_PATH" -- set 3 boot on
export DISK_PART_ROOT="${DISK_PATH}p1"
export DISK_PART_SWAP="${DISK_PATH}p2"
export DISK_PART_BOOT="${DISK_PATH}p3"

info "Formatting boot partition ..."
mkfs.fat -F 32 -n boot "$DISK_PART_BOOT"

info "Creating '$ZFS_POOL' ZFS pool for '$DISK_PART_ROOT' ..."
zpool create -f "$ZFS_POOL" "$DISK_PART_ROOT"

info "Enabling compression for '$ZFS_POOL' ZFS pool ..."
zfs set compression=on "$ZFS_POOL"

# Check if the disk is an SSD and enable autotrim if it is
if is_ssd "${DISK}"; then
    info "Detected SSD: Enabling ZFS autotrim for '$ZFS_POOL' pool ..."
    zpool set autotrim=on "$ZFS_POOL"
    info "ZFS autotrim enabled for optimal SSD performance"
else
    info "Detected rotational disk (HDD): Skipping ZFS autotrim"
fi

info "Creating '$ZFS_DS_ROOT' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_ROOT"

info "Configuring extended attributes setting for '$ZFS_DS_ROOT' ZFS dataset ..."
zfs set xattr=sa "$ZFS_DS_ROOT"

info "Configuring access control list setting for '$ZFS_DS_ROOT' ZFS dataset ..."
zfs set acltype=posixacl "$ZFS_DS_ROOT"

info "Creating '$ZFS_BLANK_SNAPSHOT' ZFS snapshot ..."
zfs snapshot "$ZFS_BLANK_SNAPSHOT"

info "Mounting '$ZFS_DS_ROOT' to /mnt ..."
mount -t zfs "$ZFS_DS_ROOT" /mnt

info "Mounting '$DISK_PART_BOOT' to /mnt/boot ..."
mkdir /mnt/boot
mount -t vfat "$DISK_PART_BOOT" /mnt/boot

info "Creating '$ZFS_DS_NIX' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_NIX"

info "Disabling access time setting for '$ZFS_DS_NIX' ZFS dataset ..."
zfs set atime=off "$ZFS_DS_NIX"

info "Mounting '$ZFS_DS_NIX' to /mnt/nix ..."
mkdir /mnt/nix
mount -t zfs "$ZFS_DS_NIX" /mnt/nix

info "Creating '$ZFS_DS_HOME' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_HOME"

info "Mounting '$ZFS_DS_HOME' to /mnt/home ..."
mkdir /mnt/home
mount -t zfs "$ZFS_DS_HOME" /mnt/home

info "Creating '$ZFS_DS_PERSIST' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_PERSIST"

info "Mounting '$ZFS_DS_PERSIST' to /mnt/persist ..."
mkdir /mnt/persist
mount -t zfs "$ZFS_DS_PERSIST" /mnt/persist

info "Permit ZFS auto-snapshots on ${ZFS_SAFE}/* datasets ..."
zfs set com.sun:auto-snapshot=true "$ZFS_DS_HOME"
zfs set com.sun:auto-snapshot=true "$ZFS_DS_PERSIST"

info "Creating persistent directory for host SSH keys ..."
mkdir -p /mnt/persist/etc/ssh

info "Enabling swap partiion on '$DISK_PART_SWAP' ..."
mkswap -L swap $DISK_PART_SWAP
swapon $DISK_PART_SWAP

# Generate the hardware-configuration.nix
# Copy this file out to nixosConfigurations if hardware is new
# Otherwise flake will use its own module
# wont touch configuration.nix if it already exists
info "Generating NixOS configuration (/mnt/etc/nixos/*.nix) just in case"
nixos-generate-config --root /mnt

info "copy out the /mnt/etc/nixos/hardware-configuration.nix if new hardware"
info "nixos-install --flake ~/code/systems#driver"
