# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, lib, pkgs, modulesPath, disko, ... }: {
  imports =
    [
      (modulesPath + "/profiles/qemu-guest.nix")
      disko.nixosModules.disko
      ./disk-config.nix
      ../_common/base/default.nix
      ../_common/services/kubernetes.nix
    ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Necessary in most configurations
  nixpkgs.config.allowUnfree = true;

  nix.settings.trusted-users = [ "rramirez" ];

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  boot.loader.grub = {
    enable = true;
    device = "nodev";  # Do not install to MBR
    useOSProber = true;
    efiSupport = false;
    zfsSupport = true;
  };

  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking = {
    hostName = "ssdnodes-1";
    hostId = "dc0b54b4";
    useDHCP = false;

    # Static IP configuration for IPv4 and IPv6
    interfaces.enp3s0 = {  # Using the same interface name as in netplan
      useDHCP = false;
      ipv4.addresses = [{
        address = "172.93.51.14";
        prefixLength = 24;
      }];
      ipv6.addresses = [{
        address = "2602:ff16:1:0:1:f:0:1";
        prefixLength = 64;
      }];
    };

    # Default gateways
    defaultGateway = {
      address = "172.93.51.1";
      interface = "enp3s0";
    };
    defaultGateway6 = {
      address = "2602:ff16:1::1";
      interface = "enp3s0";
    };

    # Cloudflare DNS servers (both IPv4 and IPv6)
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
  };

  # DNS services
  services.resolved = {
    enable = true;
    domains = [ "~." ];
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "docker" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.extraRules = [
    {
      users = ["rramirez"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  # Enable the OpenSSH daemon.
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

  programs.ssh = {
    # Fix timeout from client side
    # Ref: https://www.cyberciti.biz/tips/open-ssh-server-connection-drops-out-after-few-or-n-minutes-of-inactivity.html
    extraConfig = ''
      Host *
        ServerAliveInterval 15
        ServerAliveCountMax 3
    '';
  };

  # ZFS
  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
    };
    autoSnapshot = {
      enable = true;
      monthly = 3;
    };
  };

  services.cron = {
    enable = true;
    # Clean up nixOS generations
    # NOTE: Still requires a nix-rebuild switch to update grub
    # List generations: nix-env --list-generations -p /nix/var/nix/profiles/system
    systemCronJobs = [
      "0 1 * * * root nix-env --delete-generations +10 -p /nix/var/nix/profiles/system 2>&1 | logger -t generations-cleanup"
    ];
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
