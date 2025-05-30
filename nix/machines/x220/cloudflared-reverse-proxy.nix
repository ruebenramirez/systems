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
      "15faeae2-f7b9-404b-a7be-9d74694dbb8d" = {
        credentialsFile = "/persist/cloudflared/15faeae2-f7b9-404b-a7be-9d74694dbb8d.json";

        ingress = {
          "code.rueb.dev" = "http://127.0.0.1:3000";

          "monicaandrueben.com" = "http://127.0.0.1:8012";
          "www.monicaandrueben.com" = "http://127.0.0.1:8012";

          "monicarosephotography.com" = "http://127.0.0.1:8011";
          "www.monicarosephotography.com" = "http://127.0.0.1:8011";

        };

        # Default response for unmatched requests
        default = "http_status:404";
      };
    };
  };
}
