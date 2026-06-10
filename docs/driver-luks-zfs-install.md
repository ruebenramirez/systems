# Driver LUKS/ZFS Install

This documents the destructive install flow for the `driver` ThinkPad. It uses LUKS2 disk encryption, two FIDO2 YubiKey enrollments, a long recovery passphrase, LVM, encrypted swap, and a ZFS root pool.

## Warning

This process destroys the target disk. Verify the disk name before running the bootstrap script.

Example target disk names:

```text
nvme0n1
sda
```

## Disk Layout

The resulting layout is:

```text
/dev/<disk>1        EFI system partition, vfat, mounted at /boot
/dev/<disk>2        LUKS2 container
  /dev/mapper/cryptroot
    LVM VG cryptvg
      /dev/cryptvg/swap  encrypted swap, 32G
      /dev/cryptvg/zfs   ZFS pool zroot
```

The ZFS datasets are:

```text
zroot/local/root     /
zroot/local/nix      /nix
zroot/safe/home      /home
zroot/safe/persist   /persist
```

## Prerequisites

Boot a NixOS installer environment with working network access and the required tools available:

```text
cryptsetup
systemd-cryptenroll
lvm2
zfs
parted
dosfstools
```

Have both YubiKeys ready before starting.

## Run Bootstrap

From this repo, run the script as root with the target disk name, not the full `/dev/...` path:

```bash
sudo scripts/_bootstrap-nixos.sh nvme0n1
```

The script will ask for a LUKS passphrase during `cryptsetup luksFormat`. Use a long recovery passphrase. This is the break-glass unlock method if both YubiKeys are unavailable.

The script then enrolls two YubiKeys with FIDO2. Each YubiKey is enrolled into the same LUKS2 header.

Expected LUKS unlock model:

```text
Recovery passphrase: initial luksFormat keyslot
YubiKey 1: FIDO2 enrollment
YubiKey 2: FIDO2 enrollment
```

## Driver Config

Before running `nixos-install`, update `nix/machines/driver/hardware-configuration.nix` with the UUIDs printed by the bootstrap script.

Do not commit active placeholder UUIDs. Use the actual values printed by the install run.

Required LUKS config:

```nix
boot.initrd.systemd.enable = true;

boot.initrd.luks.devices.cryptroot = {
  device = "/dev/disk/by-uuid/<LUKS-UUID>";
  preLVM = true;
  allowDiscards = true;
  crypttabExtraOpts = [
    "fido2-device=auto"
  ];
};
```

Required boot, swap, and hibernate resume config:

```nix
fileSystems."/boot" = {
  device = "/dev/disk/by-uuid/<BOOT-UUID>";
  fsType = "vfat";
  options = [ "fmask=0022" "dmask=0022" ];
};

swapDevices = [
  { device = "/dev/disk/by-uuid/<SWAP-UUID>"; }
];

boot.resumeDevice = "/dev/disk/by-uuid/<SWAP-UUID>";
```

Keep the existing ZFS filesystem entries:

```nix
fileSystems."/" = {
  device = "zroot/local/root";
  fsType = "zfs";
};

fileSystems."/nix" = {
  device = "zroot/local/nix";
  fsType = "zfs";
};

fileSystems."/home" = {
  device = "zroot/safe/home";
  fsType = "zfs";
};

fileSystems."/persist" = {
  device = "zroot/safe/persist";
  fsType = "zfs";
};
```

After updating the config, install:

```bash
nixos-install --flake ~/code/systems#driver
```

## Why The Config Matters

`boot.initrd.luks.devices.cryptroot` tells the initrd how to unlock the encrypted root stack.

`boot.initrd.systemd.enable = true` uses systemd initrd, which supports LUKS tokens enrolled with `systemd-cryptenroll`.

`preLVM = true` is the default for LUKS devices. With systemd initrd, systemd handles the unlock ordering before the root filesystem is mounted.

`crypttabExtraOpts = [ "fido2-device=auto" ]` tells systemd-cryptsetup to use an available FIDO2 token enrolled in the LUKS2 header.

`allowDiscards = true` allows TRIM/discard commands to pass through LUKS to the SSD.

`boot.resumeDevice` is needed because `driver` uses `suspend-then-hibernate`.

## Break-Glass Passphrase

The recovery passphrase does not bypass disk encryption. It bypasses the YubiKey requirement by unlocking a normal LUKS keyslot.

Use the recovery passphrase when:

- both YubiKeys are unavailable
- a YubiKey is broken
- FIDO2 unlock regresses after an update
- you need to recover data from a live USB

Store the recovery passphrase somewhere durable and offline from the encrypted laptop.

## TRIM And Discards

TRIM is enabled by default for `driver`.

The bootstrap script enables ZFS autotrim on SSDs. The NixOS config uses `allowDiscards = true` so those discards can pass through LUKS to the SSD.

This helps with long-term SSD performance and wear behavior. The tradeoff is that someone with raw disk access may infer approximate free-space and allocation patterns. This does not expose plaintext, filenames, or passphrases, and it does not bypass encryption.

## Suspend And Hibernate

Normal suspend is not meaningfully affected by LUKS. The system remains powered, RAM still contains the unlocked keys, and the encrypted devices stay open.

Hibernate is different. The hibernate image is written to encrypted swap, and resume needs initrd to unlock LUKS, activate LVM, and find the configured swap resume device.

`driver` has 32GB RAM and uses a 32GB encrypted swap LV. This is acceptable for the current workload because RAM is not normally heavily used. If hibernate resume becomes unreliable, increase the swap LV size during reprovisioning.

## Verification

Before install, verify the provisioned storage:

```bash
cryptsetup luksDump /dev/disk/by-uuid/<LUKS-UUID>
lsblk -f
zpool status
```

After install, test these boot paths:

```text
Boot with YubiKey 1
Boot with YubiKey 2
Boot with neither YubiKey and enter the recovery passphrase
```

Also verify mounts and swap:

```bash
findmnt /
findmnt /nix
findmnt /home
findmnt /persist
swapon --show
```

## Live USB Recovery

From a NixOS live environment, unlock and mount the system with:

```bash
cryptsetup open /dev/disk/by-uuid/<LUKS-UUID> cryptroot
vgchange -ay cryptvg
zpool import -N zroot
mount -t zfs zroot/local/root /mnt
mkdir -p /mnt/boot /mnt/nix /mnt/home /mnt/persist
mount -t vfat /dev/disk/by-uuid/<BOOT-UUID> /mnt/boot
mount -t zfs zroot/local/nix /mnt/nix
mount -t zfs zroot/safe/home /mnt/home
mount -t zfs zroot/safe/persist /mnt/persist
```

If FIDO2 unlock is unavailable in the live environment, use the recovery passphrase when `cryptsetup open` prompts.

## YubiKey Maintenance

Inspect LUKS slots:

```bash
cryptsetup luksDump /dev/disk/by-uuid/<LUKS-UUID>
```

Enroll another FIDO2 YubiKey:

```bash
systemd-cryptenroll --fido2-device=auto --fido2-with-user-presence=true /dev/disk/by-uuid/<LUKS-UUID>
```

Remove a slot after verifying which slot should be removed:

```bash
systemd-cryptenroll /dev/disk/by-uuid/<LUKS-UUID> --wipe-slot=<slot>
```

Do not remove the recovery passphrase slot unless another tested recovery method exists.

## Troubleshooting

If boot cannot unlock the disk, confirm `boot.initrd.luks.devices.cryptroot.device` uses the LUKS partition UUID, not the boot partition UUID or swap UUID.

If ZFS does not import, confirm LUKS unlock and LVM activation happened before ZFS import. The install uses systemd initrd so systemd can unlock the LUKS device before mounting the ZFS root filesystem.

If hibernate does not resume, confirm `boot.resumeDevice` matches the encrypted swap LV UUID and that the swap LV is large enough for the current workload.

If YubiKey unlock fails, test the recovery passphrase first, then inspect LUKS slots with `cryptsetup luksDump`.
