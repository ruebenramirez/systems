{ config, lib, systems-secrets, ... }: {

  # Cloudflare token for DNS-01 on *.rueb.dev and the two photography wildcards.
  # Lives in a shared secrets file (recipient-listed per machine) rather than
  # homeserver.yaml, because the same token also authorises ssdnodes-1's zones.
  sops.secrets.cloudflare-token = {
    sopsFile = "${systems-secrets}/secrets/cloudflare-dns-management.yaml";
  };

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
