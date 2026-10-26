{ config, systems-secrets, ... }:

{
  # Cloudflare API token used for DNS-01 challenges on this host
  # (monicarosephotography.com, monicaandrueben.com).
  #
  # Declared once here and referenced by each `*-reverse-proxy.nix` so the two
  # ACME certs share a single credential. This replaces the plaintext
  # `/persist/secrets/cloudflare-token` that predated sops adoption on this box.
  #
  # The token now lives in a shared file rather than this host's own secrets file,
  # because one Cloudflare token covers every zone this fleet depends on. Access
  # is granted by the recipient list in `cloudflare-dns-management.yaml`, so a new
  # consumer has to be added explicitly instead of the secret being copied.
  sops.secrets.cloudflare-token = {
    sopsFile = "${systems-secrets}/secrets/cloudflare-dns-management.yaml";
  };
}
