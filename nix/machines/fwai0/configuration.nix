{ config, lib, pkgs, ... }:

{
  imports =
    [
      ../_common/base/default.nix
      ../_common/dev.nix
      ../_common/gpu-amd.nix
      ../_common/home-vpn-client.nix
      ../_common/rust-dev.nix
      ./hardware-configuration.nix
      ./services/local-llm-framework-desktop.nix
    ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  nix.settings.trusted-users = [ "rramirez" ];

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';


  networking = {
    hostName = "fwai0";
    hostId = "7f603e2c";

    # disable NetworkManager
    networkmanager.enable = false;

    # use systemd.networkd full stop
    useNetworkd = true;

    # The global useDHCP flag is deprecated, therefore explicitly set to false here.
    # Per-interface useDHCP will be mandatory in the future, so this generated config
    # replicates the default behaviour.
    useDHCP = false;

    # Make sure that dhcpcd doesnt timeout when interfaces are down
    # ref: https://nixos.org/manual/nixos/stable/options.html#opt-networking.dhcpcd.wait
    dhcpcd.wait = "if-carrier-up";

    # 1g gigabyte ethernet (built-into laptop)
    # interfaces.enp191s0.useDHCP = true;

    # 2.5g Ethernet usb-c dongle
    interfaces.enp195s0f4u1.useDHCP = true;

  };

  programs.nm-applet.enable = true;

  # DNS services
  services.resolved = {
    enable = true;
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" "1.0.0.1" ]; # cloudflare dns
  };
  services.avahi.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "adbusers"
      "audio"
      "docker"
      "renderer"
      "sound"
      "video"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
    ];
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
  # List services that you want to enable:
  # Open ports in the firewall.
  #networking.firewall.allowedTCPPorts = [
  #  ...
  #];

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
  system.stateVersion = "25.11"; # Did you read the comment?
}
