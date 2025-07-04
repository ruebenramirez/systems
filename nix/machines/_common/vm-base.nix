{ config, pkgs, ... }:
{

  # Enable IP forwarding (required for routing features)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Enable QEMU guest agent
  services.qemuGuest.enable = true;
  services.spice-vdagentd.enable = true;

  # Enable SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  # Enable Tailscale
  services.tailscale.enable = true;

  # Networking and firewall
  networking.firewall = {
    enable = true;

    trustedInterfaces = [ "tailscale0" ];

    allowedTCPPorts = [ 22 ];
    allowedUDPPorts = [ config.services.tailscale.port ];

    # fix most NixOS exit node usage issues
    checkReversePath = "loose";
  };

  # Default user
  users.users.rramirez = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
    ];
  };

  # Enable sudo without password for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Essential packages
  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    htop
    tmux
  ];

  # Enable nftables for better IPv6 support
  networking.nftables.enable = true;

  # DNS configuration to avoid common issues
  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [ "8.8.8.8" "8.8.4.4" ];
  };

  system.stateVersion = "25.05";
}
