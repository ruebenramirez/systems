{ pkgs, ... }:

{
  services.searx = {
    enable = true;
    package = pkgs.searxng;

    environmentFile = "/persist/secrets/searx-secret-key";

    settings = {
      use_default_settings = {
        engines = {
          keep_only = [
            "duckduckgo"
          ];
        };
      };

      server = {
        bind_address = "127.0.0.1";
        port = 11188;
        secret_key = "@SEARXNG_SECRET@";

        # Private local service for Open WebUI.
        limiter = false;
        public_instance = false;
      };

      search = {
        safe_search = 0;
        autocomplete = "";
        formats = [ "html" "json" ];
      };

      engines = [
        {
          name = "duckduckgo";
          disabled = false;
          timeout = 10.0;
        }
      ];

      outgoing = {
        request_timeout = 10.0;
        pool_connections = 10;
        pool_maxsize = 10;
      };
    };
  };


  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."search.rueb.dev" = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:11188";
        proxyWebsockets = true;
      };
    };
  };
}
