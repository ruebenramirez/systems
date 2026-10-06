{ config, pkgs, ... }:

{

  # List services that you want to enable:
  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    4096 # opencode headless server
    6419 # grip - markdown to web server rendering
    8888 # opencode web session
  ];
  networking.firewall.interfaces.tailscale0.allowedUDPPorts = [
  ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;
}
