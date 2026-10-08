{ pkgs-unstable, lib, ... }:
{
  services.tailscale.derper = {
    enable = true;
    domain = "derp.rueb.dev";
    package = pkgs-unstable.tailscale.derper;
    configureNginx = true;
    openFirewall = true;      # UDP/3478 STUN
    verifyClients = true;
  };
  # DERP must keep answering on :80 (derper uses it) but hand its TLS listener
  # to the HAProxy/nginx-fronted topology on loopback :8444 (PROXY protocol).
  services.nginx.virtualHosts."derp.rueb.dev" = {
    enableACME = true;  # HTTP-01
    listen = lib.mkForce [
      { addr = "0.0.0.0"; port = 80; }
      { addr = "[::0]"; port = 80; }
      { addr = "127.0.0.1"; port = 8444; ssl = true; proxyProtocol = true; }
      { addr = "[::1]"; port = 8444; ssl = true; proxyProtocol = true; }
    ];
  };

  services.tailscale.extraSetFlags = [
    "--relay-server-port=40000"
    "--relay-server-static-endpoints=172.93.51.14:40000,[2602:ff16:1:0:1:f:0:1]:40000"
  ];
  networking.firewall.allowedUDPPorts = [ 40000 ];
}