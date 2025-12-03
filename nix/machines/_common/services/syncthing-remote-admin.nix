{ config, pkgs, ... }:

{
  services = {
      syncthing = {
          enable = true;
          guiAddress = "0.0.0.0:8384";
          user = "rramirez";
          dataDir = "/home/rramirez/Sync";
          configDir = "/home/rramirez/.config/syncthing";
      };
  };

  networking.firewall.allowedTCPPorts = [
    8384  # webui
    22000 # sync
  ];
  networking.firewall.allowedUDPPorts = [
    21027 # LAN discovery
    22000 # sync
  ];

}
