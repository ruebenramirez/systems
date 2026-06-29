{ config, pkgs, ... }:

{

  # List services that you want to enable:
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [

  ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}

