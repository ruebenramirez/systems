{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/dev.nix
    ../_common/home-vpn-client.nix
    ../_common/rust-dev.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Enable IP forwarding (required for routing features)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  fileSystems."/" = {
    device = "/dev/vda2";
    fsType = "ext4"; # This is the default for nixos-generators QCOW2 images
  };
  fileSystems."/boot" = {
    device = "/dev/vda1";
    fsType = "vfat";
  };

  time.timeZone = "America/Chicago";

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  networking = {
    hostName = "dev-vm-xps";
    firewall.checkReversePath = "loose";
    nftables.enable = true;
    useDHCP = true;
  };

  # Enable QEMU guest agent
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  # DNS services
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
  programs.ssh = {
    # Fix timeout from client side
    # Ref: https://www.cyberciti.biz/tips/open-ssh-server-connection-drops-out-after-few-or-n-minutes-of-inactivity.html
    extraConfig = ''
      Host *
        ServerAliveInterval 15
        ServerAliveCountMax 3
    '';
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
  system.stateVersion = "25.11";
}
