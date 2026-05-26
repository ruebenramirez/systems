{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
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
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" ];

  fileSystems."/" = {
    device = lib.mkForce "/dev/vda2";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = lib.mkForce "/dev/vda1";
    fsType = "vfat";
  };

  time.timeZone = "America/Chicago";

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  networking = {
    hostName = "newsletter-dev-vm";
    useNetworkd = true;
    interfaces.enp1s0.useDHCP = true;
    nftables.enable = true;
    useDHCP = false;
    firewall = {
      allowedTCPPorts = [
        80
        443
      ];
      checkReversePath = "loose";
    };
  };

  systemd.services."serial-getty@ttyS0" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
  };

  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  services.resolved = {
    enable = true;
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" "1.0.0.1" ];
  };
  services.avahi.enable = true;

  nix.settings.trusted-users = [ "newsletter-dev-bot" "rramirez" ];

  users.groups.newsletter-dev-bot = {};
  users.users.newsletter-dev-bot = {
    isSystemUser = true;
    uid = 1001;
    group = "newsletter-dev-bot";
    extraGroups = [ "docker" ];
    home = "/var/lib/newsletter-dev-bot";
    createHome = true;
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTMf83tSsZW9wkwOSebkoQjPwPSx35tzMM0wmVDatPh" ];
  };
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
