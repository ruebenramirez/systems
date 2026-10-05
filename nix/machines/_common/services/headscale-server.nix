{ config, pkgs, pkgs-unstable, ... }:

{
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.headscale = {
    enable = true;
    package = pkgs-unstable.headscale;

    address = "127.0.0.1";
    port = 8090;

    settings = {
      server_url = "https://hs.rueb.dev";

      # Keep the Prometheus metrics endpoint on loopback only.
      metrics_listen_addr = "127.0.0.1:9090";

      # Explicit SQLite database with WAL mode enabled.
      database = {
        type = "sqlite";
        sqlite.write_ahead_log = true;
      };

      dns = {
        magic_dns = true;
        base_domain = "tailnet.rueb.dev";
        override_local_dns = true;
        nameservers.global = [ "1.1.1.1" "1.0.0.1" ];
      };

      policy.mode = "database";
    };
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."hs.rueb.dev" = {
      forceSSL = true;
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:8090";
        proxyWebsockets = true;
        # Tailnet control plane holds long-lived connections; don't cut at 60s.
        extraConfig = ''
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };
  };
}
