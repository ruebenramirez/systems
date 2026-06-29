{ config, pkgs, ... }:

{

  # List services that you want to enable:
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.allowedTCPPorts = [
    80
    443
    139
    445
    8089
    9008
  ];
  networking.firewall.allowedUDPPorts = [
    137
    138
  ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
