# Minimal Raspberry Pi 4 Configuration

{ config, lib, pkgs, pkgs-unstable, modulesPath, ... }:

{
  imports = [
    ../_common/base/default.nix
    ./zfs-backups.nix
  ];

  # Basic system identification
  networking = {
    hostName = "raspberry-pi";
    hostId = "42eb57a2";  # Generate a unique 8-char hex ID

    # Networking patch for Tailscale exit node usage
    # Remove warning from tailscale:
    #  Strict reverse path filtering breaks Tailscale exit node use
    #    and some subnet routing setups
    firewall.checkReversePath = "loose";
    # tailscale exit node usage on ipv6
    nftables.enable = true;
    networkmanager.enable = true;
  };

  # Time zone
  time.timeZone = "America/Chicago";

  # Essential user configuration
  users.users = {
    # Keep nixos user for initial access
    nixos = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
      ];
    };

    # Your regular user
    rramirez = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "wheel" "audio" "video" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
      ];
    };
  };

  # Sudo configuration
  security.sudo.wheelNeedsPassword = false;

  # Nix settings
  nix = {
    settings = {
      trusted-users = [ "nixos" "rramirez" ];
      substituters = [ "https://nix-community.cachix.org" ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  boot = {
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
    supportedFilesystems = [ "zfs" ];
    initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];
    initrd.supportedFilesystems = [ "zfs" ];
    kernelPackages = pkgs.linuxPackages_rpi4;
    kernelModules = [ "zfs" ];
    initrd.kernelModules = [ "zfs" ];

    # load up tankbak zpool for syncoid snapshot replication from homeserver
    zfs.extraPools = [ "tankbak" ];
  };

  sdImage = {
    compressImage = false;
    expandOnBoot = true;
    populateFirmwareCommands = "";
    populateRootCommands = "";
  };

  hardware = {
    enableRedistributableFirmware = true;
    enableAllHardware = lib.mkForce false;
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";  # For initial setup only
      PasswordAuthentication = true;  # Temporary for initial setup
    };
  };

  system.stateVersion = "25.05";
}
