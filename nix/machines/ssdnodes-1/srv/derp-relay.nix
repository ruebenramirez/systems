{ pkgs-unstable, ... }:
{
  services.tailscale.derper = {
    enable = true;
    domain = "derp.rueb.dev";
    package = pkgs-unstable.tailscale.derper;
    configureNginx = true;
    openFirewall = true;      # UDP/3478 STUN
    verifyClients = true;
  };
  services.nginx.virtualHosts."derp.rueb.dev".enableACME = true;  # HTTP-01

  services.tailscale.extraSetFlags = [
    "--relay-server-port=40000"
    "--relay-server-static-endpoints=172.93.51.14:40000,[2602:ff16:1:0:1:f:0:1]:40000"
  ];
  networking.firewall.allowedUDPPorts = [ 40000 ];
}