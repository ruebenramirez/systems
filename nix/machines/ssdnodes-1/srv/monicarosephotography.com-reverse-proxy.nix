{ config, pkgs, lib, ... }:

{
  # ---------------------------------------------------------------------------
  # Shared Group for Wildcard TLS Certificate
  # ---------------------------------------------------------------------------
  users.groups."monicarosephotography-tls" = {};

  # ---------------------------------------------------------------------------
  # TLS: Certificate for monicarosephotography.com and *.monicarosephotography.com
  # via Cloudflare DNS-01 challenge.
  # Requires a Cloudflare API token with Zone:Zone:Read + Zone:DNS:Edit scope
  # ---------------------------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = "postmaster@rueb.dev";

    certs."monicarosephotography.com" = {
      # Explicitly declare both the root domain and the wildcard to ensure coverage
      domain = "monicarosephotography.com";
      extraDomainNames = [ "*.monicarosephotography.com" ];
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = "/persist/secrets/cloudflare-token";
      };
      group = "monicarosephotography-tls";
    };
  };

  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "monicarosephotography-tls" ];

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."monicarosephotography.com" = {
      # Route both the root domain and the www subdomain to this virtual host
      serverAliases = [ "www.monicarosephotography.com" ];
      forceSSL = true;

      # Use the certificate defined in the acme block
      useACMEHost = "monicarosephotography.com";

      locations."/" = {
        proxyPass = "http://127.0.0.1:8011";
        proxyWebsockets = true;
      };
    };
  };
}
