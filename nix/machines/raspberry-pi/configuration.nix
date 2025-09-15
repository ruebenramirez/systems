# Minimal Raspberry Pi 4 Configuration
# This is a more conservative approach that's less likely to have build issues

{ config, lib, pkgs, pkgs-unstable, modulesPath, ... }:

{
  # Import only essential modules initially
  imports = [
    # Start with just base configuration
    ../_common/base/default.nix
    ./zfs-backups.nix
  ];

  # Basic system identification
  networking = {
    hostName = "raspberry-pi";
    hostId = "42eb57a2";  # Generate a unique 8-char hex ID

    # Use simple wireless configuration initially
    wireless = {
      enable = true;
      # You can configure networks here or use wpa_supplicant.conf
      # networks = {
      #   "YourSSID" = {
      #     psk = "YourPassword";
      #   };
      # };
    };

    # Disable NetworkManager initially to avoid conflicts
    networkmanager.enable = false;
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

  # Minimal boot configuration - use defaults as much as possible
  boot = {
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    # Use default kernel (generic aarch64) instead of Pi-specific
    # This avoids the module issues you're seeing

    # Minimal kernel modules
    initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];

    # Disable ZFS
    supportedFilesystems.zfs = lib.mkForce false;
  };

  # SD Image configuration - keep it simple
  sdImage = {
    compressImage = false;
    expandOnBoot = true;

    # Make sure we don't include unnecessary firmware
    populateFirmwareCommands = "";
    populateRootCommands = "";
  };

  # Essential hardware support
  hardware = {
    enableRedistributableFirmware = true;
  };

  # SSH configuration
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "yes";  # For initial setup only
      PasswordAuthentication = true;  # Temporary for initial setup
    };
  };

  # Minimal package set
  environment.systemPackages = with pkgs; [
    # Keep it minimal initially
    wget
    curl
    htop
    nano  # Simpler than vim for initial setup
  ];

  # System state version
  system.stateVersion = "25.05";
}
