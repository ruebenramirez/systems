{ config, pkgs, ... }:

{

  networking = {
    nftables.enable = true;
    # List services that you want to enable:
    # Open ports in the firewall.
    # networking.firewall.allowedTCPPorts = [ ... ];
    # networking.firewall.allowedUDPPorts = [ ... ];
    firewall.allowedTCPPorts = [
      1313 # hugo blog dev
      6419 # grip - markdown to web server rendering
      8765 # timer web app dev
    ];
    firewall.allowedUDPPorts = [
    ];
    # Or disable the firewall altogether.
    # networking.firewall.enable = false;
  };
}
