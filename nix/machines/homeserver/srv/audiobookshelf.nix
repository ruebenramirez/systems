{ config, pkgs, pkgs-unstable, ... }:

let

in
{
  services.audiobookshelf = {
    enable = true;
    host = "0.0.0.0";
    port = 13378;
    package = pkgs-unstable.audiobookshelf;
    user = "rramirez";
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

    virtualHosts."audiobooks.rueb.dev" = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:13378";
        proxyWebsockets = true;
      };
    };
  };

}
