{ config, ... }: {
  disko.devices = {
    disk.sda = {
      device = "/dev/sda";
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          # BIOS boot partition (required for GRUB with GPT)
          bios_boot = {
            size = "1M";
            type = "EF02";  # BIOS boot partition type
          };
          # /boot partition (separate from ZFS for reliability)
          boot = {
            name = "boot";
            size = "512M";
            type = "8300";  # Linux filesystem
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/boot";
            };
          };
          # ZFS partition (uses remaining space)
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool";  # This is the pool name
            };
          };
        };
      };
    };
  };

  # Define the ZFS pool properties and datasets
  disko.devices.zpool.rpool = {
    type = "zpool";

    # Pool-level properties
    options = {
      ashift = "12";
      autotrim = "on";
    };

    # Filesystem-level properties
    rootFsOptions = {
      acltype = "posixacl";
      relatime = "on";
      xattr = "sa";
      dnodesize = "auto";
      normalization = "formD";
      mountpoint = "none";
      canmount = "off";
      compression = "lz4";
    };

    datasets = {
      "nixos/root" = {
        type = "zfs_fs";
        mountpoint = "/";
        options = {
          mountpoint = "legacy";
        };
      };
      "nixos/nix" = {
        type = "zfs_fs";
        mountpoint = "/nix";
        options = {
          mountpoint = "legacy";
          atime = "off";
        };
      };
      "nixos/home" = {
        type = "zfs_fs";
        mountpoint = "/home";
        options = {
          mountpoint = "legacy";
        };
      };
      "nixos/var" = {
        type = "zfs_fs";
        mountpoint = "/var";
        options = {
          mountpoint = "legacy";
        };
      };
      "nixos/persist" = {
        type = "zfs_fs";
        mountpoint = "/persist";
        options = {
          mountpoint = "legacy";
        };
      };
    };
  };
}
