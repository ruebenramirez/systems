{ config, ... }:

{
  # Cloudflare API token used for DNS-01 challenges on this host
  # (monicarosephotography.com, monicaandrueben.com).
  #
  # Declared once here and referenced by each `*-reverse-proxy.nix` so the two
  # ACME certs share a single credential. This replaces the plaintext
  # `/persist/secrets/cloudflare-token` that predated sops adoption on this box.
  #
  # NOTE: this is a *different* token from the one on `homeserver`
  # (`homeserver.yaml:cloudflare-token`, which issues the `rueb.dev` wildcard).
  # Rotating one does not rotate the other.
  sops.secrets.cloudflare-token = { };
}
