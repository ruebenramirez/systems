{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
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
    hostName = "forgejo-ci-runner-vm";
    useNetworkd = true;
    interfaces.enp1s0.useDHCP = true;
    nftables.enable = true;
    useDHCP = false;
    firewall.checkReversePath = "loose";
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

  virtualisation.docker.enable = true;

  services.gitea-actions-runner.instances.forgejo-ci-runner-vm = {
    enable = true;
    name = "forgejo-ci-runner-vm";
    url = "https://code.rueb.dev";
    tokenFile = "/run/keys/forgejo-runner-token";
    labels = [
      "nixos-x86_64:host"
      "native:host"
      "ubuntu-latest:docker://node:20-bookworm"
      "debian-latest:docker://node:20-bookworm"
    ];
    hostPackages = with pkgs; [
      bash
      coreutils
      curl
      gawk
      gitMinimal
      gnused
      nodejs
      wget
    ];
  };

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
