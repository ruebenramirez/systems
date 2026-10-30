{ config, lib, systems-secrets, ... }:
let
  # Without a default file, a secret that does not name its own file would
  # silently resolve to nothing at deploy time instead of failing here.
  missingFile =
    lib.attrNames (lib.filterAttrs (_: s: s.sopsFile == null) config.sops.secrets);
in
{
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # Secrets live in per-service files, so there is no default file to fall back
  # to: which file a key comes from is part of the access decision, not a detail.
  # Every declaration must name it, via `secretFile "<service-file>"`.
  assertions = [
    {
      assertion = missingFile == [ ];
      message = ''
        These sops secrets do not name a sopsFile: ${lib.concatStringsSep ", " missingFile}
        Set one, e.g. sops.secrets.foo = secretFile "stalwart-server-homeserver";
      '';
    }
  ];
}
