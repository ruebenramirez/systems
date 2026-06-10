#!/usr/bin/env bash

# Ref: https://gist.github.com/mx00s/ea2462a3fe6fdaa65692fe7ee824de3e
# NixOS install script synthesized from:
#
#   - Erase Your Darlings (https://grahamc.com/blog/erase-your-darlings)
#   - ZFS Datasets for NixOS (https://grahamc.com/blog/nixos-on-zfs)
#   - NixOS Manual (https://nixos.org/nixos/manual/)
#
# It expects the name of the block device (e.g. 'nvme0n1') to partition
# and install NixOS on.
#
# Example: `setup.sh nvme0n1`
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
  sleep 5
  swapoff -a
  vgchange -an cryptvg
  sleep 2
  cryptsetup close cryptroot
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
    err "Missing argument. Expected block device name, e.g. 'nvme0n1'"
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

# Handle partition naming schemes (nvme0n1p1 vs sda1)
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    PART_SUFFIX="p"
else
    PART_SUFFIX=""
fi

export DISK_PART_BOOT="${DISK_PATH}${PART_SUFFIX}1"
export DISK_PART_LUKS="${DISK_PATH}${PART_SUFFIX}2"

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

info "Running the UEFI (GPT) partitioning directions ..."
parted -s "$DISK_PATH" -- mklabel gpt
parted -s "$DISK_PATH" -- mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK_PATH" -- set 1 boot on
parted -s "$DISK_PATH" -- mkpart primary 512MiB 100%

info "Formatting boot partition ..."
mkfs.fat -F 32 -n boot "$DISK_PART_BOOT"
BOOT_UUID="$(blkid -s UUID -o value "$DISK_PART_BOOT")"

info "Setting up LUKS2 encryption on $DISK_PART_LUKS"
info "You will be prompted to set a recovery password first."
cryptsetup luksFormat --type luks2 "$DISK_PART_LUKS"
LUKS_UUID="$(cryptsetup luksUUID "$DISK_PART_LUKS")"

info "Opening LUKS container ..."
cryptsetup open "$DISK_PART_LUKS" cryptroot

info "Enrolling YubiKey 1 (FIDO2) ..."
echo -e "${BLUE_BG}Please plug in your FIRST YubiKey and press Enter.${COLOR_RESET}"
read -r
systemd-cryptenroll --fido2-device=auto --fido2-with-user-presence=true "$DISK_PART_LUKS"

info "Enrolling YubiKey 2 (FIDO2) ..."
echo -e "${BLUE_BG}Please unplug the first YubiKey, plug in your SECOND YubiKey, and press Enter.${COLOR_RESET}"
read -r
systemd-cryptenroll --fido2-device=auto --fido2-with-user-presence=true "$DISK_PART_LUKS"

info "Setting up LVM inside LUKS container for Swap and ZFS ..."
pvcreate /dev/mapper/cryptroot
vgcreate cryptvg /dev/mapper/cryptroot
lvcreate -L 32G -n swap cryptvg
lvcreate -l 100%FREE -n zfs cryptvg

info "Formatting and enabling encrypted swap partition ..."
mkswap -L swap /dev/cryptvg/swap
SWAP_UUID="$(blkid -s UUID -o value /dev/cryptvg/swap)"
swapon /dev/cryptvg/swap

info "Creating '$ZFS_POOL' ZFS pool for root ..."
zpool create -f "$ZFS_POOL" /dev/cryptvg/zfs

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
mkdir -p /mnt/boot
mount -t vfat "$DISK_PART_BOOT" /mnt/boot

info "Creating '$ZFS_DS_NIX' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_NIX"

info "Disabling access time setting for '$ZFS_DS_NIX' ZFS dataset ..."
zfs set atime=off "$ZFS_DS_NIX"

info "Mounting '$ZFS_DS_NIX' to /mnt/nix ..."
mkdir -p /mnt/nix
mount -t zfs "$ZFS_DS_NIX" /mnt/nix

info "Creating '$ZFS_DS_HOME' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_HOME"

info "Mounting '$ZFS_DS_HOME' to /mnt/home ..."
mkdir -p /mnt/home
mount -t zfs "$ZFS_DS_HOME" /mnt/home

info "Creating '$ZFS_DS_PERSIST' ZFS dataset ..."
zfs create -p -o mountpoint=legacy "$ZFS_DS_PERSIST"

info "Mounting '$ZFS_DS_PERSIST' to /mnt/persist ..."
mkdir -p /mnt/persist
mount -t zfs "$ZFS_DS_PERSIST" /mnt/persist

info "Permit ZFS auto-snapshots on ${ZFS_SAFE}/* datasets ..."
zfs set com.sun:auto-snapshot=true "$ZFS_DS_HOME"
zfs set com.sun:auto-snapshot=true "$ZFS_DS_PERSIST"

info "Creating persistent directory for host SSH keys ..."
mkdir -p /mnt/persist/etc/ssh

# Generate the hardware-configuration.nix
# Copy this file out to nixosConfigurations if hardware is new
# Otherwise flake will use its own module
# wont touch configuration.nix if it already exists
info "Generating NixOS configuration (/mnt/etc/nixos/*.nix) just in case"
nixos-generate-config --root /mnt

info "LUKS/ZFS provisioning values for driver"
cat <<EOF
BOOT_UUID=${BOOT_UUID}
LUKS_UUID=${LUKS_UUID}
SWAP_UUID=${SWAP_UUID}

Enrollment model:
- Initial luksFormat passphrase: long break-glass recovery passphrase
- YubiKey 1: FIDO2 LUKS enrollment
- YubiKey 2: FIDO2 LUKS enrollment

Before running nixos-install, update nix/machines/driver/hardware-configuration.nix
with the real UUIDs above. Do not leave placeholder UUIDs in active config.

Required driver NixOS snippet:

  boot.initrd.systemd.enable = true;

  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-uuid/${LUKS_UUID}";
    preLVM = true;
    allowDiscards = true;
    crypttabExtraOpts = [
      "fido2-device=auto"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/${BOOT_UUID}";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [
    { device = "/dev/disk/by-uuid/${SWAP_UUID}"; }
  ];

  boot.resumeDevice = "/dev/disk/by-uuid/${SWAP_UUID}";

Verification commands:

  cryptsetup luksDump "$DISK_PART_LUKS"
  lsblk -f
  zpool status

After updating driver hardware config, install with:

  nixos-install --flake ~/code/systems#driver
EOF
