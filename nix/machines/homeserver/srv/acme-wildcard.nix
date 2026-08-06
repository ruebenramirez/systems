{ config, lib, systems-secrets, ... }: {

  # declare sops secret for cloudflare-token secret
  sops.secrets.cloudflare-token = { };

  # ---------------------------------------------------------------------------
  # Shared Group for Wildcard TLS Certificate
  # ---------------------------------------------------------------------------
  users.groups."ruebdev-wildcard-tls" = {};

  # ---------------------------------------------------------------------------
  # TLS: Wildcard certificate for *.rueb.dev via Cloudflare DNS-01 challenge.
  # Requires a Cloudflare API token with Zone:Zone:Read + Zone:DNS:Edit scope
  # ---------------------------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = "postmaster@rueb.dev";

    certs."rueb.dev" = {
      domain = "*.rueb.dev";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-token.path;
      };
      group = "ruebdev-wildcard-tls";
    };
    certs."monicaandrueben.com" = {
      domain = "*.monicaandrueben.com";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-token.path;
      };
      group = "ruebdev-wildcard-tls";
    };
    certs."monicarosephotography.com" = {
      domain = "*.monicarosephotography.com";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare-token.path;
      };
      group = "ruebdev-wildcard-tls";
    };
  };
}
