{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/exit-node-monitor.nix
    ../_common/monitoring.nix
    ../_common/nix-deploy-user.nix
    ../_common/qemu-vm-guest.nix
    ../_common/mullvad-vpn-client.nix
    ../_common/tailscale-client.nix
  ];

  # Advertise this VM as an exit node; approval is via autoApprovers tag:exit.
  services.tailscale.extraSetFlags = [ "--advertise-exit-node" ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Enable IP forwarding (required for routing features)
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # Disk layout (disko)
  boot.growPartition = true;
  disko.memSize = 1024;
  disko.imageBuilder.imageFormat = "qcow2";
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "download-vm-xps";
    imageSize = "250G";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  networking = {
    hostName = "download-vm-xps";
    firewall = {
      enable = true;
      allowedTCPPorts = [ 49164 ];
      allowedUDPPorts = [ 6881 ]; # DHT needs UDP!
    };
  };

  # Torrent stack: rtorrent daemon with SCGI API (/run/rtorrent/rpc.sock) +
  # Flood web UI (first visit creates the admin account). Peer port matches
  # the existing UDP 6881 rule; openFirewall adds TCP.
  services.rtorrent = {
    enable = true;
    port = 6881;
    openFirewall = true;
    # Group-writable data so Flood (rtorrent group) can manage files.
    dataPermissions = "0770";
    # Override the template's conservative private-tracker defaults; the umask
    # makes new torrent dirs group-writable too.
    configText = ''
      dht.mode.set = auto
      protocol.pex.set = yes
      trackers.use_udp.set = yes
      system.umask.set = 0007
    '';
  };

  services.flood = {
    enable = true;
    port = 3000;
    host = "0.0.0.0"; # firewall gates it to tailscale0 only
    extraArgs = [
      "--rtsocket=${config.services.rtorrent.rpcSocket}"
      "--allowedpath=/var/lib/rtorrent"
    ];
  };

  # Flood talks to rtorrent over the SCGI socket, which is group-writable for
  # the rtorrent group (RuntimeDirectoryMode 750).
  systemd.services.flood.serviceConfig.SupplementaryGroups = [ config.services.rtorrent.group ];

  # Web UI reachable over the tailnet only.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 3000 ];

  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "audio" "networkmanager" "sound" "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea" ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
