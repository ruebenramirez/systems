{ config, lib, pkgs, pkgs-unstable, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/qemu-vm-guest.nix
    ../_common/dev.nix
    ../_common/tailscale-client.nix
    ../_common/services/kubernetes.nix
    ./services/forgejo-runner.nix
    ./services/nup-fleet-access.nix
    # The runner is itself a `MACHINES` entry, so it must trust its own
    # fleet deploy key to update itself as part of `nup-fleet all`.
    ../_common/nix-deploy-user.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Disk layout (disko); sized for the CI flake checkout and nix store growth.
  boot.growPartition = true;
  disko.memSize = 8192;
  disko.imageBuilder.imageFormat = "qcow2";
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "forgejo-ci-runner-vm";
    imageSize = "500G";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  networking = {
    hostName = "forgejo-ci-runner-vm";
  };

  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "docker" "networkmanager" "sound" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.wheelNeedsPassword = false;

  # host-mode CI jobs need nixos-rebuild on PATH (nix comes from dev.nix)
  environment.systemPackages = [ pkgs.nixos-rebuild-ng ];

  system.stateVersion = "25.11";
}
