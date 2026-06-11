# NixOS ZFS Install

This documents the destructive ZFS install flow used by `scripts/_bootstrap-nixos.sh`.

The script supports two root disk layouts:

```text
default       unencrypted ZFS root
--luks        LUKS2 encrypted root with two FIDO2 YubiKeys
```

LUKS root encryption is optional. Most machines can continue using the default unencrypted ZFS root flow. Use `--luks` only when encrypted root is desired.

## Warning

This process destroys the target disk. Verify the disk name before running the bootstrap script.

Example target disk names:

```text
sda
nvme0n1
```

## Usage

Default unencrypted ZFS root:

```bash
sudo scripts/_bootstrap-nixos.sh <disk>
```

Encrypted LUKS root:

```bash
sudo scripts/_bootstrap-nixos.sh <disk> --luks
```

Examples:

```bash
sudo scripts/_bootstrap-nixos.sh sda
sudo scripts/_bootstrap-nixos.sh sda --luks
sudo scripts/_bootstrap-nixos.sh nvme0n1
sudo scripts/_bootstrap-nixos.sh nvme0n1 --luks
```

For NVMe disks, the script uses partition names such as `/dev/nvme0n1p1` and `/dev/nvme0n1p2`. For SATA-style disks, it uses names such as `/dev/sda1` and `/dev/sda2`.

## Default Layout

Without `--luks`, the layout is:

```text
/dev/<disk>1  EFI system partition, vfat, mounted at /boot
/dev/<disk>2  ZFS pool zroot
```

The script does not create swap in the default unencrypted mode.

## LUKS Layout

With `--luks`, the layout is:

```text
/dev/<disk>1        EFI system partition, vfat, mounted at /boot
/dev/<disk>2        LUKS2 container
  /dev/mapper/cryptroot
    LVM VG cryptvg
      /dev/cryptvg/swap  encrypted swap, 32G
      /dev/cryptvg/zfs   ZFS pool zroot
```

The initial `cryptsetup luksFormat` passphrase is the break-glass recovery passphrase. The script then enrolls two FIDO2 YubiKeys into the same LUKS2 header.

Expected LUKS unlock model:

```text
Recovery passphrase: initial luksFormat keyslot
YubiKey 1: FIDO2 enrollment
YubiKey 2: FIDO2 enrollment
```

## ZFS Datasets

Both modes create the same datasets:

```text
zroot/local/root     /
zroot/local/nix      /nix
zroot/safe/home      /home
zroot/safe/persist   /persist
```

## Unencrypted Config

After the script finishes in default mode, update the target machine's `hardware-configuration.nix` with the printed boot UUID.

Required boot config:

```nix
fileSystems."/boot" = {
  device = "/dev/disk/by-uuid/<BOOT-UUID>";
  fsType = "vfat";
  options = [ "fmask=0022" "dmask=0022" ];
};

swapDevices = [ ];
```

Keep the ZFS filesystem entries pointed at the dataset names:

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

## LUKS Config

After the script finishes in `--luks` mode, update the target machine's `hardware-configuration.nix` with the printed boot, LUKS, and swap UUIDs.

Do not commit active placeholder UUIDs. Use the actual values printed by the install run.

Required LUKS config:

```nix
boot.initrd.systemd.enable = true;
boot.initrd.systemd.fido2.enable = true;

boot.initrd.luks.devices.cryptroot = {
  device = "/dev/disk/by-uuid/<LUKS-UUID>";
  preLVM = true;
  allowDiscards = true;
  crypttabExtraOpts = [
    "fido2-device=auto"
  ];
};
```

Required boot and swap config:

```nix
fileSystems."/boot" = {
  device = "/dev/disk/by-uuid/<BOOT-UUID>";
  fsType = "vfat";
  options = [ "fmask=0022" "dmask=0022" ];
};

swapDevices = [
  { device = "/dev/disk/by-uuid/<SWAP-UUID>"; }
];
```

Use this on machines that hibernate, such as `driver`:

```nix
boot.resumeDevice = "/dev/disk/by-uuid/<SWAP-UUID>";
```

`x220` does not currently require `boot.resumeDevice` unless hibernate is enabled there.

## Why The LUKS Config Matters

`boot.initrd.systemd.enable = true` uses systemd initrd, which supports LUKS tokens enrolled with `systemd-cryptenroll`.

`boot.initrd.systemd.fido2.enable = true` includes the FIDO2 udev rules and cryptsetup token plugin in the initrd.

`boot.initrd.luks.devices.cryptroot` tells initrd how to unlock the encrypted root stack.

`crypttabExtraOpts = [ "fido2-device=auto" ]` tells systemd-cryptsetup to use an available FIDO2 token enrolled in the LUKS2 header.

`allowDiscards = true` allows TRIM/discard commands to pass through LUKS to the SSD.

`boot.resumeDevice` is needed for hibernate resume from encrypted swap.

## x220 Validation Flow

Use `x220` as the first validation target before applying encrypted root to `driver`.

Run the encrypted flow on the x220 installer:

```bash
sudo scripts/_bootstrap-nixos.sh <x220-disk> --luks
```

Update:

```text
nix/machines/x220/hardware-configuration.nix
```

Install:

```bash
nixos-install --flake ~/code/systems#x220
```

Real validation checklist:

```text
Boot with YubiKey 1
Boot with YubiKey 2
Boot without YubiKey using the recovery passphrase
Verify ZFS mounts
Verify encrypted swap is active
Verify zpool status
Verify autotrim if the disk is an SSD
```

Useful checks after boot:

```bash
findmnt /
findmnt /nix
findmnt /home
findmnt /persist
swapon --show
zpool status
zpool get autotrim zroot
cryptsetup luksDump /dev/disk/by-uuid/<LUKS-UUID>
```

Do not treat the encrypted process as fully validated until this x220 install and boot testing succeeds.

## Driver Rollout Flow

After x220 validation succeeds, run the encrypted flow on `driver`:

```bash
sudo scripts/_bootstrap-nixos.sh nvme0n1 --luks
```

Update:

```text
nix/machines/driver/hardware-configuration.nix
```

Include `boot.resumeDevice` because `driver` uses `suspend-then-hibernate`.

Install:

```bash
nixos-install --flake ~/code/systems#driver
```

## Break-Glass Passphrase

The recovery passphrase does not bypass disk encryption. It bypasses the YubiKey requirement by unlocking a normal LUKS keyslot.

Use the recovery passphrase when:

- both YubiKeys are unavailable
- a YubiKey is broken
- FIDO2 unlock regresses after an update
- you need to recover data from a live USB

Store the recovery passphrase somewhere durable and offline from the encrypted laptop.

## TRIM And Discards

The script enables ZFS autotrim on detected SSDs.

For `--luks` installs, the printed NixOS config includes `allowDiscards = true` so discards can pass through LUKS to the SSD.

This helps with long-term SSD performance and wear behavior. The tradeoff is that someone with raw disk access may infer approximate free-space and allocation patterns. This does not expose plaintext, filenames, or passphrases, and it does not bypass encryption.

## Suspend And Hibernate

Normal suspend is not meaningfully affected by LUKS. The system remains powered, RAM still contains the unlocked keys, and the encrypted devices stay open.

Hibernate is different. The hibernate image is written to encrypted swap, and resume needs initrd to unlock LUKS, activate LVM, and find the configured swap resume device.

`driver` has 32GB RAM and uses a 32GB encrypted swap LV. This is acceptable for the current workload because RAM is not normally heavily used. If hibernate resume becomes unreliable, increase the swap LV size during reprovisioning.

## Live USB Recovery For LUKS Installs

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

If boot cannot unlock a LUKS install, confirm `boot.initrd.luks.devices.cryptroot.device` uses the LUKS partition UUID, not the boot partition UUID or swap UUID.

If FIDO2 unlock fails, confirm both `boot.initrd.systemd.enable` and `boot.initrd.systemd.fido2.enable` are enabled.

If ZFS does not import on a LUKS install, confirm LUKS unlock and LVM activation happened before ZFS import.

If hibernate does not resume, confirm `boot.resumeDevice` matches the encrypted swap LV UUID and that the swap LV is large enough for the current workload.

If YubiKey unlock fails, test the recovery passphrase first, then inspect LUKS slots with `cryptsetup luksDump`.
