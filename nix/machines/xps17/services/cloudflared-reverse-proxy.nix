# cloudflared.nix
{ config, lib, pkgs, pkgs-unstable, ... }:

{

  environment.systemPackages = with pkgs-unstable; [
    pkgs-unstable.cloudflared
  ];

  # Enable the Cloudflare tunnel daemon
  services.cloudflared = {
    enable = true;
    package = pkgs-unstable.cloudflared;

    # Configure your tunnel - use your actual UUID
    tunnels = {
      "459c9edd-ceba-4e65-b5a0-c77b5af24939" = {
        credentialsFile = "/persist/cloudflared/459c9edd-ceba-4e65-b5a0-c77b5af24939.json";

        ingress = {
          "photos.monicaandrueben.com" = "http://127.0.0.1:3001";
        };

        # Default response for unmatched requests
        default = "http_status:404";
      };
    };
  };
}
