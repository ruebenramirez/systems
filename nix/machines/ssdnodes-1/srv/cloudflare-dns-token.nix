{ secretFile, ... }:

{
  # Cloudflare API token used for DNS-01 challenges on this host
  # (monicarosephotography.com, monicaandrueben.com).
  #
  # Declared once here and referenced by each `*-reverse-proxy.nix` so the two
  # ACME certs share a single credential. This replaces the plaintext
  # `/persist/secrets/cloudflare-token` that predated sops adoption on this box.
  #
  # One Cloudflare token covers every zone this fleet depends on, so it lives in
  # a shared file. Access is granted by the recipient list in
  # `cloudflare-dns-client.yaml`, so a new consumer has to be added explicitly
  # instead of the secret being copied.
  sops.secrets.cloudflare-token = secretFile "cloudflare-dns-client";
}
