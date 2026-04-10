{ config, pkgs, pkgs-unstable, lib, ... }:

{
  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.kavita = {
    enable = true;

    # Path to the 512+ bit secret key file
    tokenKeyFile = "/persist/secrets/kavita-token.key";

    # Custom state directory on ZFS pool
    dataDir = "/tank/srv/ebooks-kavita";

    # Free-form attribute set matching appsettings.json configuration
    settings = {
      # Bind to 127.0.0.1 since we are using Nginx as a reverse proxy
      IpAddresses = "127.0.0.1";
      Port = 5000;
    };
    package = pkgs-unstable.kavita;
  };

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."ebooks.rueb.dev" = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:5000";
        proxyWebsockets = true;
      };
    };
  };
}
