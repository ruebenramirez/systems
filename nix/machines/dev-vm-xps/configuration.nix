{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/nix-deploy-user.nix
    ../_common/qemu-vm-guest.nix
    ../_common/dev.nix
    ../_common/tailscale-client.nix
    ../_common/rust-dev.nix
    ../_common/services/kubernetes.nix
    ../_common/vm-nfs-client.nix
    # Offload all builds to fwai0; no local compilation.
    ./remote-builder-fwai0.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Enable IP forwarding (required for routing features)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Disk layout (disko)
  boot.growPartition = true;
  disko.memSize = 8192;
  disko.imageBuilder.imageFormat = "qcow2";
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "dev-vm-xps";
    imageSize = "200G";
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
    hostName = "dev-vm-xps";
  };

  # data share from homeserver tank -> /mnt/data
  my.vmNfsClient.mounts.data = { };

  networking.firewall.allowedTCPPorts = [
    5173
    8000
  ];

  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "docker" "networkmanager" "sound" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
