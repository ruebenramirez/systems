{ lib, pkgs, ... }:

let
  restrictedRsync = pkgs.writeShellScript "hosted-sites-backup-source" ''
    exec ${lib.getExe pkgs.rrsync} -ro /srv
  '';
in
{
  services.openssh.settings.PermitRootLogin = lib.mkForce "forced-commands-only";

  users.users.root.openssh.authorizedKeys.keys = [
    ''from="100.64.0.1/32",restrict,command="${restrictedRsync}" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAFxSjzbTH+xZ0uuydd7lra7ka3JeZLvkmQZ3X6fy2xL homeserver-hosted-sites-backup''
  ];
}
