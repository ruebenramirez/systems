{ config, pkgs, lib, ... }:

{
  # ---------------------------------------------------------------------------
  # Shared Group for Wildcard TLS Certificate
  # ---------------------------------------------------------------------------
  users.groups."monicaandrueben-tls" = {};

  # ---------------------------------------------------------------------------
  # TLS: Certificate for monicaandrueben.com and *.monicaandrueben.com
  # via Cloudflare DNS-01 challenge.
  # Requires a Cloudflare API token with Zone:Zone:Read + Zone:DNS:Edit scope
  # ---------------------------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = "postmaster@rueb.dev";

    certs."monicaandrueben.com" = {
      domain = "monicaandrueben.com";
      extraDomainNames = [ "*.monicaandrueben.com" ];
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = "/persist/secrets/cloudflare-token";
      };
      group = "monicaandrueben-tls";
    };
  };

  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "monicaandrueben-tls" ];

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."monicaandrueben.com" = {
      serverAliases = [ "www.monicaandrueben.com" ];
      forceSSL = true;

      # Use the certificate defined in the acme block
      useACMEHost = "monicaandrueben.com";

      locations."/" = {
        proxyPass = "http://127.0.0.1:8012";
        proxyWebsockets = true;
      };
    };
  };
}
