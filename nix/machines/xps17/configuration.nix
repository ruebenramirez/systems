{ config, lib, pkgs, ... }:

{
  imports = [
    ../_common/base/default.nix
    #../_common/desktop/default.nix
    ../_common/dev.nix
    #../_common/fingerprint-reader.nix
    #../_common/gaming.nix
    #../_common/gpu-nvidia.nix
    ../_common/home-vpn-client.nix
    ../_common/services/kubernetes.nix
    ../_common/services/virtualization-intel.nix
    ../_common/physical.nix
    ../_common/build-machine.nix
    ./hardware-configuration.nix
    #./services/local-llm-Nvidia.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking = {
    hostName = "xps17";
    hostId = "6f602d2c";

    networkmanager.enable = false;
    wireless.enable = false;
    nftables.enable = true;

    useNetworkd = true;

    # The global useDHCP flag is deprecated, therefore explicitly set to false here.
    # Per-interface useDHCP will be mandatory in the future, so this generated config
    # replicates the default behaviour.
    useDHCP = false;

    # Make sure that dhcpcd doesnt timeout when interfaces are down
    # ref: https://nixos.org/manual/nixos/stable/options.html#opt-networking.dhcpcd.wait
    dhcpcd.wait = "if-carrier-up";

    # 2.5g Ethernet usb-c dongle as bridge to physical network
    bridges."br0".interfaces = [ "enp0s13f0u4" ];
    interfaces.enp0s13f0u4.useDHCP = false;
    interfaces.br0.useDHCP = true;
  };

  # Define a user account. Don't forget to set a password with 'passwd'.
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

  # if laptop lid closes
  services.logind.settings.Login.HandleLidSwitch = "ignore";        # clamshell w/out power
  services.logind.settings.Login.HandleLidSwitchDocked = "ignore";  # clamshell w/ power

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.11"; # Did you read the comment?
}
