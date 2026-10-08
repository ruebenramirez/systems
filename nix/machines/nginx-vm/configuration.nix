{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/qemu-vm-guest.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.growPartition = true;

  # Disk layout (disko)
  disko.memSize = 1024;
  disko.imageBuilder.imageFormat = "qcow2";
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "nginx-vm";
    imageSize = "10G";
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
    hostName = "nginx-vm";
    firewall.allowedTCPPorts = [ 80 ];
  };

  services.openssh.enable = true;

  services.nginx = {
    enable = true;
    virtualHosts."default" = {
      default = true;
      locations."/".return = "200 hello-from-nginx-vm";
    };
  };

  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}