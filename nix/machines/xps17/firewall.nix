{ config, pkgs, ... }:

{

  # List services that you want to enable:
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.allowedTCPPorts = [
    139
    445
    8089
    8888
    9008
  ];
  networking.firewall.allowedUDPPorts = [
    137
    138
  ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Remove warning from tailscale: Strict reverse path filtering breaks Tailscale exit node use and some subnet routing setups
  networking.firewall.checkReversePath = "loose";

}
