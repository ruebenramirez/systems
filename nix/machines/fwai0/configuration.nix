{ config, lib, pkgs, ... }:

{
  imports = [
    ../_common/base/default.nix
    ../_common/monitoring.nix
    ../_common/nix-deploy-user.nix
    ../_common/build-machine.nix
    ../_common/container-mirrors.nix
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

  # fwai0 is the fleet's build host, and `pkgs.dockerTools.pullImage` is skopeo:
  # every digest-pinned image this flake builds (forgejo, webmail, wordpress,
  # mariadb, hermes-agent) is fetched here, so this is the host where putting
  # those pulls behind Harbor actually buys something (issue #51).
  my.containerMirrors.enable = true;

  # The sandbox hides /etc/containers from the build: a fixed-output build's
  # chroot only gets resolv.conf, services, hosts, nsswitch.conf and the CA
  # bundle, so skopeo inside `pullImage` would find no registries.conf and pull
  # direct. Mount the config and the drop-in dir into the sandbox (directories
  # mount recursively, so the drop-ins under registries.conf.d come with it).
  nix.settings.extra-sandbox-paths = [
    "/etc/containers/registries.conf"
    "/etc/containers/registries.conf.d"
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
