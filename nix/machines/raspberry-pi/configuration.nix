# Minimal Raspberry Pi 4 Configuration

{ config, lib, pkgs, pkgs-unstable, modulesPath, ... }:

{
  imports = [
    ../_common/base/default.nix
  ];

  time.timeZone = "America/Chicago";

  nix = {
    settings = {
      trusted-users = [ "rramirez" ];
      substituters = [ "https://nix-community.cachix.org" ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  hardware = {
    enableRedistributableFirmware = true;
    enableAllHardware = lib.mkForce false;
  };

  sdImage = {
    compressImage = false;
    expandOnBoot = true;
    populateFirmwareCommands = "";
    populateRootCommands = "";
  };

  users.users = {
    rramirez = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "audio" "networkmanager" "video" "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
      ];
    };
  };

  security.sudo.wheelNeedsPassword = false;

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
  };

  networking = {
    hostName = "raspberry-pi";
    hostId = "42eb57a2";  # Generate a unique 8-char hex ID

    networkmanager.enable = true;

    # Networking patch for Tailscale exit node usage
    # Remove warning from tailscale:
    #  Strict reverse path filtering breaks Tailscale exit node use
    #    and some subnet routing setups
    firewall.checkReversePath = "loose";
    # tailscale exit node usage on ipv6
    nftables.enable = true;
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  system.stateVersion = "25.05";
}
