{ config, lib, pkgs, ... }:

{
  imports = [
    ../_common/base/default.nix
    ../_common/nix-deploy-user.nix
    ../_common/build-machine.nix
    ../_common/desktop/default.nix
    #../_common/gaming.nix
    ../_common/gpu-amd.nix
    ../_common/tailscale-client.nix
    #../_common/sunshine-headless.nix
    ./hardware-configuration.nix
    ./services/firewall.nix
    ./services/nix-builder-access.nix
    #./services/llama-cpp-upstream.nix
    ./services/halogen-flash-server.nix
  ];

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

    # 1g gigabyte ethernet (built-in)
    # interfaces.enp191s0.useDHCP = true;

    # 2.5g Ethernet usb-c dongle
    interfaces.enp195s0f4u1.useDHCP = true;
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "adbusers"
      "audio"
      "docker"
      "render"
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

  # Cap the ARC so halogen can pin its ~62 GiB checkpoint: at the default ARC
  # max the pre-flight check failed ~7 GiB short of the 16 GiB floor.
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=8589934592
  '';

  system.stateVersion = "25.11";
}
