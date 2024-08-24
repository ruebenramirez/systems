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
      # Import nix-garage
      #./nix-garage-overlay.nix
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

  networking.hostName = "xps17"; # Define your hostname.
  # Need to be set for ZFS or else leads to:
  # Failed assertions:
  # - ZFS requires networking.hostId to be set
  networking.hostId = "6f602d2b";

  # Disable manual configuration of wireless networking
  # # Enables wireless support via wpa_supplicant
  # networking.wireless.enable = true;
  # # Option is misleading but we dont want it
  # networking.wireless.userControlled.enable = false;
  # # Allow configuring networks "imperatively"
  # networking.wireless.allowAuxiliaryImperativeNetworks = true;

  # use network manager to configure wireless
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  #networking.useDHCP = false;

  # Make sure that dhcpcd doesnt timeout when interfaces are down
  # ref: https://nixos.org/manual/nixos/stable/options.html#opt-networking.dhcpcd.wait
  #networking.dhcpcd.wait = "if-carrier-up";
  #networking.interfaces.enp2s0f0.useDHCP = true;
  #networking.interfaces.enp5s0.useDHCP = true;
  #networking.interfaces.wlp3s0.useDHCP = true;

  # Leave commented until tether is needed
  #networking.interfaces.enp7s0f4u2.useDHCP = true;

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Audio
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true;

  # 1password system authentication
  security.polkit.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "rramirez" ];
  };

  # use Fish shell
  users.defaultUserShell = pkgs.fish;
  programs.fish.enable = true;
  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" "audio" "sound" "docker" ]; # Enable ‘sudo’ for the user.
    openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDFeq0/IpNsLCUDVhxRx/wEj4BViCSH/8n4nhD7+PFkzuXpwKft1s5PVFJrlixv7cEJyJTi4FgeeP4N6tPglsIamplfzBjXgRTs0+ssH8ZrHM6l+0jbMqVc39hDRYl78qoxslrz3b0oU4H8bKylyOoEBO9qlJEh4bsIYkUD8ZIbaJa6g3wnPzp/WPjAG76tdoMnuxDQ1uVWph4diQxI85iwnU32anC85w6KthXQABbyV8SAYZvc7vKcN8Mf1JJSGct4nVB/XzZ3mTk3C3L0DA63f6UTtgtCZAXIsqhjeGahp+QUBIgrFG5fG1o5hmHgyHZuOIrbU1BbH/mWpaXbGUut rramirez@le-laptop" ];
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
      #pinentry
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

  # part of gnupg reqs
  services.pcscd.enable = true;
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    #pinentryFlavor = "tty";
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
  networking.firewall.allowedTCPPorts = [ 24800 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

# TODO: implement local firewall configuration
#   - more deets https://nixos.wiki/wiki/Firewall
# networking.firewall = {
#   enable = true;
#   allowedTCPPorts = [ 80 443 ];
#   allowedUDPPortRanges = [
#     { from = 4000; to = 4007; }
#     { from = 8000; to = 8010; }
#   ];
# };

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

  powerManagement.enable = true;

  # Enable tlp for stricter governance of power management
  # Validate status: `sudo tlp-stat -b`
  services.tlp.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?


}
