{ config, pkgs, lib, ... }:

{
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
        CLOUDFLARE_DNS_API_TOKEN_FILE = "/persist/secrets/cloudflare-token";
      };
      group = "ruebdev-wildcard-tls";
    };
    certs."monicaandrueben.com" = {
      domain = "*.monicaandrueben.com";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = "/persist/secrets/cloudflare-token";
      };
      group = "ruebdev-wildcard-tls";
    };
  };
}
