{ config, lib, pkgs, pkgs-unstable, ... }:

{
  services.cloudflared = {
    enable = true;
    package = pkgs-unstable.cloudflared;
    tunnels = {
      "459c9edd-ceba-4e65-b5a0-c77b5af24939" = {
        credentialsFile = "/persist/cloudflared/459c9edd-ceba-4e65-b5a0-c77b5af24939.json";
        ingress = {
          "photos.monicaandrueben.com" = "http://127.0.0.1:3001";
        };
        default = "http_status:404";
      };
      "15faeae2-f7b9-404b-a7be-9d74694dbb8d" = {
        credentialsFile = "/persist/cloudflared/15faeae2-f7b9-404b-a7be-9d74694dbb8d.json";

        ingress = {
          "code.rueb.dev" = "http://127.0.0.1:3000";

          "freshrss.rueb.dev" = "http://127.0.0.1:8080";

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
