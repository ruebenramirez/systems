{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./save-power-amd.nix
    ../_common/base/default.nix
    ../_common/desktop/default.nix
    ../_common/amd-gpu.nix
    ../_common/dev.nix
    ../_common/services/syncthing-remote-admin.nix
    ../_common/services/kubernetes.nix

    # virtualization services
    ../_common/services/virtualization-amd.nix
    ../_common/services/vm-scripts.nix
    ../_common/services/vm-storage.nix

    # homeserver services
    ./srv/audiobookshelf.nix
    ./srv/freshrss.nix
    ./srv/postgresql.nix
    ./srv/redis.nix
    ./srv/immich.nix
    ./srv/jellyfin.nix
    ./srv/cifs-samba-shares.nix
    ./srv/nextcloud-server.nix

    # networking
    ./srv/firewall.nix
    ./srv/cloudflared-reverse-proxy.nix
  ];

  time.timeZone = "America/Chicago";

  nix.settings = {
    trusted-users = [ "rramirez" ];

    # Set the download buffer size to 500 MB
    download-buffer-size = 524288000;
  };

  # remove the annoying experimental warnings
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking = {
    hostName = "homeserver";
    # Generate a random hostId: `openssl rand -hex 4`
    hostId = "cf24992e";

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
    fallbackDns = [ "1.1.1.1" "1.0.0.1" ]; # Default back to Cloudflare DNS
  };
  services.avahi.enable = true;

  # Users
  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "adbusers" "audio" "docker" "networkmanager" "sound" "wheel" "ydotool" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJ1wxfdli9d8p0rCgry6QD5AfhU75q5uRtiqfFG2mlu"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOgBVnhpFWDK0G7+ylfGqUUq8n2G5zc47QOaf3CSd2lP"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICLEy9lNT6rOmwOgSZjbE3GGZyDubPd6IAEZqwlnIZY8"
      # syncoid
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAoT6LnPxojekkdEDX5MxA9hpiSOK1RX95h41aK1wkX7"
    ];
  };
  security.sudo.extraRules = [ {
    users = ["rramirez"];
    commands = [ {
      command = "ALL";
      options = ["NOPASSWD"];
    } ];
  } ];

  # OpenSSH
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
  networking.firewall.allowedTCPPorts = [ 1313 ];
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

  services.sanoid = {
    enable = true;
    interval = "daily";
    datasets."tank/data" = {
      recursive = false;
      autosnap = true;
      autoprune = true;
      hourly = 0;
      daily = 7; # keeps 7 daily backups
      weekly = 4; # keeps 4 weekly backups
      monthly = 2; # keeps 2 monthly backups
      yearly = 0;
    };
  };

  environment.systemPackages = with pkgs; [ sanoid ];

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
  system.stateVersion = "25.05"; # Did you read the comment?
}
