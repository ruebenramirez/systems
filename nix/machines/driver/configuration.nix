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

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Necessary in most configurations
  nixpkgs.config.allowUnfree = true;

  nix.settings.trusted-users = [ "rramirez" ];

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  networking = {
    hostName = "P14s";
    hostId = "6f602d2b";

    # Remove warning from tailscale: Strict reverse path filtering breaks Tailscale exit node use and some subnet routing setups
    firewall.checkReversePath = "loose";
    networkmanager.enable = true;
  };
  programs.nm-applet.enable = true;

  services.resolved = {
    enable = true;
#    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1" "1.0.0.1" ];
#    extraConfig = ''
#      DNSOverTLS=yes
#    '';
  };
  services.tailscale.enable = true;

  # Audio - Enable pipewire for sound.
  sound.enable = true;
  hardware.pulseaudio.enable = false;
  services.pipewire.enable = true;
  services.pipewire.alsa.enable = true;
  services.pipewire.pulse.enable = true;

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
    extraGroups = [ "audio" "docker" "networkmanager" "sound" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
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

      # VPN
      tailscale
      openvpn

      libimobiledevice # internet via iPhone usb tethering
      fprintd # fingerprint reader
      barrier # share mouse and keyboard across multiple machines

      # media editing
      gimp-with-plugins
      inkscape-with-extensions

      # davinci-resolve # disabling because problem with python2.7 being insecure

      wine
      wine64
      winetricks
      winePackages.fonts

      toybox # strings cli to view strings in a binary file

      k3d # micro kubernetes distribution

      syncthing
      syncthingtray
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

  # internet via iPhone usb-tethering
  services.usbmuxd = {
    enable = true;
    package = pkgs.usbmuxd2;
  };

  services.avahi.enable = true;

  # firmware update
  services.fwupd.enable = true;


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

  environment.variables = {
    EDITOR="vim";
  };


  # laptop power management
  powerManagement.enable = true;
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

      # CPU performance Caps
      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 20;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 20;

      #manipulate laptop charge behavior to extend the life of the battery
      START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
    };
  };
  # Validate status: `sudo tlp-stat -b`

  # if laptop lid closes
  services.logind.lidSwitch = "suspend-then-hibernate";
  services.logind.lidSwitchExternalPower = "suspend-then-hibernate";

  # docs: https://nixos.wiki/wiki/Syncthing
  services.syncthing = {
    enable = true;
    user = "rramirez";
    dataDir = "/home/rramirez/Sync";
    configDir = "/home/rramirez/.config/syncthing";
    settings = {
      devices = {
        dev-ssdnodes = {
          id = "NIYWJNO-AUDJBM4-2FSQTPJ-PJXOYLP-TXKTCLR-TKOXG7V-H5HG7TO-LKY3QAK";
          addresses = "tcp://100.101.103.79:22000";
          autoAcceptFolders = true;
        };
#        "pixel-6-grapheneos" = { id = "2KN6SQA-TCVSWE6-FLULPEA-4H2JIQG-EOMARWC-N5Z7S6I-6BG7DEW-TYYLEAX"; };
      };
#      folders = {
#        "Default Folder" = {
#          path = "/home/rramirez/Sync";
#          devices = [ "dev-ssdnodes" ];
#        };
#      };
    };
    overrideFolders = false;
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
