{ config, pkgs, lib, ... }:

{
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
  };

  # Wildcard ACME configuration
  security.acme = {
    acceptTerms = true;
    defaults.email = "postmaster@rueb.dev";

    certs."rueb.dev" = {
      domain = "*.rueb.dev";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = "/persist/secrets/cloudflare-token";
      };
      # Assign the certificate group to nginx
      group = "nginx";
    };
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
      # Use the wildcard cert defined above
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:5000";
        proxyWebsockets = true;
      };
    };
  };
}
