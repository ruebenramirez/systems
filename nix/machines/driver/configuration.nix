# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:
let
  # Locals
in
{
  imports =
    [
      ./hardware-configuration.nix
      ../_common/desktop.nix
      ../_common/base.nix
      ./home.nix
    ];

  # Necessary in most configurations
  nixpkgs.config.allowUnfree = true;

  # temporary for obsidian support
  nixpkgs.config.permittedInsecurePackages = [ "electron-24.8.6" ];

  nix.settings.trusted-users = [ "rramirez" ];

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "P14s"; # Define your hostname.
  # Need to be set for ZFS or else leads to:
  # Failed assertions:
  # - ZFS requires networking.hostId to be set
  networking.hostId = "6f602d2b";

  # # Enables wireless support via wpa_supplicant
  # networking.wireless.enable = true;
  # # Option is misleading but we dont want it
  # networking.wireless.userControlled.enable = false;
  # # Allow configuring networks "imperatively"
  # networking.wireless.allowAuxiliaryImperativeNetworks = true;
  networking.networkmanager.enable = true;

  programs.nm-applet.enable = true;

  networking.nameservers = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" ];
  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
    extraConfig = ''
      DNSOverTLS=yes
    '';
  };

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;

  # Make sure that dhcpcd doesnt timeout when interfaces are down
  # ref: https://nixos.org/manual/nixos/stable/options.html#opt-networking.dhcpcd.wait
  #networking.dhcpcd.wait = "if-carrier-up";
  #networking.interfaces.enp2s0f0.useDHCP = true;
  #networking.interfaces.enp5s0.useDHCP = true;
  networking.interfaces.wlp2s0.useDHCP = true;

  # Leave commented until tether is needed
  #networking.interfaces.enp7s0f4u2.useDHCP = true;

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Audio
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true;

  # Bluetooth
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;


  # use Fish shell
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" "audio" "sound" "docker" "networkmanager" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea rramirez@xps17" ];
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

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment = {
    systemPackages = with pkgs; [
      awscli2
      gh
      glab
      ticker # stocks
      newsboat
      icdiff
      imagemagick
      magic-wormhole
      nixpkgs-review
      # hardware key
      gnupg
      pcsclite
      pinentry
      tailscale # VPN
      openvpn # VPN
      libimobiledevice # internet via iPhone usb tethering
      fprintd # fingerprint reader
      barrier # share mouse and keyboard across multiple machines
      networkmanagerapplet # network manager system tray applet
      # media editing
      gimp-with-plugins
      inkscape-with-extensions
      # davinci-resolve # disabling because problem with python2.7 being insecure
      wine
      wine64
      winetricks
      winePackages.fonts
      toybox # strings cli to view strings in a binary file
    ];

    etc."wpa_supplicant.conf" = {
      source = "/persist/etc/wpa_supplicant.conf";
      mode = "symlink";
    };
  };

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

  services.cron = {
    enable = true;
    # Clean up nixOS generations
    # NOTE: Still requires a nix-rebuild switch to update grub
    # List generations: nix-env --list-generations -p /nix/var/nix/profiles/system
    systemCronJobs = [
      "0 1 * * * root nix-env --delete-generations +10 -p /nix/var/nix/profiles/system 2>&1 | logger -t generations-cleanup"
    ];
  };

  # firmware update
  services.fwupd.enable = true;

  # Dont start tailscale by default
  services.tailscale.enable = true;
  # Remove warning from tailscale: Strict reverse path filtering breaks Tailscale exit node use and some subnet routing setups
  networking.firewall.checkReversePath = "loose";

  #services.logind.extraConfig = "HandleLidSwitch=ignore";

  # part of gnupg reqs
  services.pcscd.enable = true;
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    pinentryFlavor = "tty";
    # Make pinentry across multiple terminal windows, seamlessly
    enableSSHSupport = true;
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
  # networking.firewall.allowedTCPPorts = [ ... ];
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

  virtualisation.docker.enable = true;

  systemd.services.zfs-scrub.unitConfig.ConditionACPower = true;

  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 20;
    };
  };

  # dont hiberate/sleep by default
  powerManagement.enable = true;
  # Enable tlp for stricter governance of power management
  # Validate status: `sudo tlp-stat -b`
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?


  # fingerprint reader configuration
  services.fprintd.enable = true;
  services.fprintd.tod.enable = true;
  services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix;
  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      wantedBy = [ "graphical-session.target" ];
      wants = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
    };
  };
  # 1password system (fingerprint) auth
  security.polkit.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "rramirez" ];
  };


  # redshift configuration

  location = {
	provider = "manual";
	latitude = 30.266666;
	longitude = -97.733330;
  };
  # All values except 'enable' are optional.
  services.redshift = {
    enable = true;
    brightness = {
      # Note the string values below.
      day = "1";
      night = "1";
    };
    temperature = {
      day = 5500;
      night = 1500;
    };
  };

  environment.variables = {
    EDITOR="vim";
  };

}
