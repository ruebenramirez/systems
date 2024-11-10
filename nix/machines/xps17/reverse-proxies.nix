{ config, pkgs, ... }:

{
  # Enable Tailscale
  services.tailscale = {
    enable = true;

    # Enable the Tailscale serve feature
    useRoutingFeatures = "server";

    # Configure serve settings
    extraUpFlags = [
      "--accept-dns=false"
      "--advertise-exit-node"
    ];
  };

  # Configure the Tailscale serve service
  systemd.services.tailscale-serve = {
    description = "Tailscale HTTPS Server";
    wantedBy = [ "multi-user.target" ];
    wants = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --https=443 http://localhost:8888";
      Restart = "always";
      RestartSec = "5";
    };
  };

  # Open required ports
  networking.firewall = {
    enable = true;
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts = [ config.services.tailscale.port ];
    allowedTCPPorts = [ 443 ];  # For HTTPS
  };
}
