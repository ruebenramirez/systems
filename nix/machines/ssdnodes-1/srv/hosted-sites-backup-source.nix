{ lib, pkgs, ... }:

let
  restrictedRsync = pkgs.writeShellScript "hosted-sites-backup-source" ''
    exec ${lib.getExe pkgs.rrsync} -ro /srv
  '';
in
{
  services.openssh.settings.PermitRootLogin = lib.mkForce "forced-commands-only";

  users.users.root.openssh.authorizedKeys.keys = [
    ''from="10.100.0.0/24",restrict,command="${restrictedRsync}" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHRRWuu2DEfhiE/IKpZn4VmUI6WVKxE/V9OP8/xzjvw8 homeserver-hosted-sites-backup''
  ];
}
