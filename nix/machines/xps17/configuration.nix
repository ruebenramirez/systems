{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./zfs-backups.nix
    ../_common/nvidia-graphics.nix
    ../_common/base/default.nix
    ../_common/desktop/default.nix
    ../_common/fingerprint-reader.nix
    ../_common/gaming.nix
    ../_common/services/kubernetes.nix
    ../_common/services/syncthing-remote-admin.nix
  ];

  time.timeZone = "America/Chicago";

  nix.settings.trusted-users = [ "rramirez" ];

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking = {
    hostName = "xps17";
    hostId = "6f602d2c";

    # Networking patch for Tailscale exit node usage
    # Remove warning from tailscale:
    #  Strict reverse path filtering breaks Tailscale exit node use
    #    and some subnet routing setups
    firewall.checkReversePath = "loose";
    # tailscale exit node usage on ipv6
    nftables.enable = true;
    networkmanager.enable = true;
  };

  # DNS services
  services.resolved = {
    enable = true;
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" "1.0.0.1" ];
  };
  services.avahi.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "docker" "networkmanager" "sound" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.extraRules = [ {
    users = ["rramirez"];
    commands = [ {
        command = "ALL";
        options = ["NOPASSWD"];
    }];
  } ];

  # SSH
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
  systemd.services.zfs-scrub.unitConfig.ConditionACPower = true;


  # firmware update
  services.fwupd.enable = true;

  # laptop power management
  powerManagement.enable = true;
  services.tlp = {
    enable = true;
    settings = {
      # Optimize for performance while on AC.
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      # Optimize for battery runtime while on battery.
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      # extend the life of the battery (I'm always plugged in anyways)
      START_CHARGE_THRESH_BAT0 = 40; # 40 and below it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
    };
  };
  # Validate status: `sudo tlp-stat -b`

  # if laptop lid closes (disable clamshell mode)
  services.logind.lidSwitch = "suspend-then-hibernate";
  services.logind.lidSwitchDocked = "suspend-then-hibernate";

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
