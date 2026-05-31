{ config, pkgs, ... }:

{
  imports =
    [
      ../_common/android.nix
      ../_common/base/default.nix
      ../_common/build-machine.nix
      ../_common/desktop/default.nix
      ../_common/dev.nix
      ../_common/fingerprint-reader.nix
      ../_common/gaming.nix
      ../_common/gpu-amd.nix
      ../_common/home-vpn-client.nix
      ../_common/mullvad-client.nix
      ../_common/rust-dev.nix
      ../_common/desktop/razer-keyboard.nix
      ./hardware-configuration.nix
      ./mtp-storage-access.nix
      ./udev-rules/lofree-keyboard-udev-disable-thinkpad-keyboard.nix
      ./udev-rules/xreal-udev-unplug-restart-kanshi.nix
    ];

  # Set your time zone.
  time.timeZone = "America/Chicago";

  nix.settings.trusted-users = [ "rramirez" ];

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;

  # Limit the number of generations kept in /boot to prevent partition exhaustion
  boot.loader.systemd-boot.configurationLimit = 10;

  boot.loader.efi.canTouchEfiVariables = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking = {
    hostName = "driver";
    hostId = "6f602d2b";
    networkmanager.enable = false;

    wireless = {
      enable = true;
      enableHardening = false;
      extraConfigFiles = [
        "/persist/etc/wpa_supplicant.conf"
      ];
      extraConfig = ''
        ctrl_interface=DIR=/run/wpa_supplicant GROUP=wheel
        update_config=1
      '';
      userControlled = true;
      interfaces = [ "wlp2s0" ];
    };
    useNetworkd = true;
    useDHCP = false;
  };
  systemd.network.networks = {
    # Wi-Fi Interface
    "30-wireless" = {
      matchConfig.Name = "wlp2s0";
      networkConfig.DHCP = "yes";
    };
    # Built-in 1G Ethernet
    "40-ethernet-built-in" = {
      matchConfig.Name = "enp1s0f0";
      networkConfig.DHCP = "yes";
    };

    # # USB-C 2.5G Ethernet Dongles
    # "50-usb-ethernet-1" = {
    #   matchConfig.Name = "enp102s0f3u*";
    #   networkConfig.DHCP = "yes";
    # };
  };

  # DNS services
  services.resolved = {
    enable = true;
    settings.Resolve = {
      Domains = [ "~." ];
      FallbackDNS = [ "1.1.1.1" "1.0.0.1" ]; # cloudflare dns
    };
  };

  systemd.network.wait-online = {
    enable = true;
    anyInterface = true;
    ignoredInterfaces = [ "wg0" "wg1" ];
    timeout = 30;
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
      "network"
      "openrazer"
      "renderer"
      "sound"
      "video"
      "wheel"
      "ydotool"
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
  networking.firewall.allowedTCPPorts = [
    #1313  # hugo blog dev
  ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

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
      # disable boost to save external usb-c pd battery bank power
      CPU_BOOST_ON_AC = 0;
      CPU_BOOST_ON_BAT = 0;

      # Optimize for battery while on AC.
      #   (run laptop frequently on external battery packs)
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_AC = "power";

      # Optimize for battery runtime while on battery.
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      # extend the life of the battery (I'm always plugged in anyways)
      START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
    };
    # Validate status: `sudo tlp-stat -b`
  };

  # if laptop lid closes
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  # clamshell w/out power
  #services.logind.settings.Login.HandleLidSwitch = "ignore";
  # clamshell w/ power
  #services.logind.settings.Login.HandleLidSwitchDocked = "ignore";

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
  system.stateVersion = "24.05"; # Did you read the comment?
}
