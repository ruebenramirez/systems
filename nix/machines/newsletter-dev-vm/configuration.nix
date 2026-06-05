{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/qemu-vm-guest.nix
    ../_common/dev.nix
    ../_common/home-vpn-client.nix
    ../_common/services/kubernetes.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Disk layout (disko)
  boot.growPartition = true;
  disko.memSize = 4096;
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "newsletter-dev-vm";
    imageSize = "32G";
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

  # VM runtime resources (consumed by deployment script)
  my.vmDeploy = {
    memoryMB = 512;
    vcpus = 2;
    bridge = "br0";
  };

  time.timeZone = "America/Chicago";

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  networking = {
    hostName = "newsletter-dev-vm";
    firewall = {
      allowedTCPPorts = [
        80
        443
      ];
    };
  };

  services.resolved = {
    enable = true;
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" "1.0.0.1" ];
  };
  services.avahi.enable = true;

  nix.settings.trusted-users = [ "rramirez" ];
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "docker" "networkmanager" "sound" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };
  programs.ssh.extraConfig = ''
    Host *
      ServerAliveInterval 15
      ServerAliveCountMax 3
  '';

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "25.11";
}
