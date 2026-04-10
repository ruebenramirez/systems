{ config, pkgs, pkgs-unstable, lib, ... }:

{
  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."code.rueb.dev" = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };
    };
  };
}
