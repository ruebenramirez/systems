{ pkgs, ... }:

let
  # Static Element Web bundle with the fleet homeserver preselected on the
  # welcome screen (the wrapper package merges this into config.json).
  elementWeb = pkgs.element-web.override {
    conf = {
      default_server_config."m.homeserver" = {
        base_url = "https://matrix.rueb.dev";
        server_name = "matrix.rueb.dev";
      };
    };
  };
in
{
  # Element is static files; the client talks to matrix.rueb.dev (ssdnodes-1)
  # directly -- the homeserver sends CORS headers, so no /_matrix proxy here.
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.nginx = {
    enable = true;
    virtualHosts."chat.rueb.dev" = {
      forceSSL = true;
      useACMEHost = "rueb.dev";
      root = elementWeb;

      locations."/" = {
        # SPA: unknown paths fall back to index.html.
        tryFiles = "$uri $uri/ /index.html =404";
      };

      # Reload-visible config, never a stale cached copy.
      locations."= /config.json" = {
        extraConfig = ''add_header Cache-Control "no-store";'';
      };

      # A stale cached index pins an old hashed bundle after a rebuild.
      locations."= /index.html" = {
        extraConfig = ''add_header Cache-Control "no-store";'';
      };
    };
  };
}
