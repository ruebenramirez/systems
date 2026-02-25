{ config, pkgs, ... }:

{
  networking.firewall = {
    allowedTCPPorts = [
      80    # HTTP (ACME challenges)
      443   # HTTPS (Matrix client-server API)
      8448  # Matrix federation
    ];
  };
}
