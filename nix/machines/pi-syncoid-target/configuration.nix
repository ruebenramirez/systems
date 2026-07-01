# Minimal Raspberry Pi 4 Configuration

{ config, lib, pkgs, pkgs-unstable, modulesPath, ... }:

{
  imports = [
    ../_common/base/default.nix
    ../_common/home-vpn-client.nix
    ../_common/physical.nix
    ./zfs-backups.nix
  ];

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
    #kernelPackages = pkgs.linuxPackages_rpi4;
    kernelModules = [ "zfs" ];
    initrd.kernelModules = [ "zfs" ];
    kernel.sysctl = {
      "vm.mmap_rnd_bits" = 24;
    };
  };

  networking = {
    hostName = "pi-syncoid-target";
    hostId = "42eb57a2";  # Generate a unique 8-char hex ID

    networkmanager.enable = true;
    nftables.enable = true;
  };

  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
  };

   system.stateVersion = "25.05";
}
