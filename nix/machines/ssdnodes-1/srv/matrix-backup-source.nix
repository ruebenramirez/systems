{ lib, pkgs, ... }:

let
  # Public half of `matrix_backup_ssh_private_key` (which lives in
  # secrets/homeserver.yaml); the homeserver pulls with the private half.
  matrixBackupPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKQQ2Z+lE5Z/XQgXDVxV/CaQDLJ2R5Yo643mts0+Sk03 homeserver-matrix-backup";

  restrictedRsync = pkgs.writeShellScript "matrix-backup-source" ''
    exec ${lib.getExe pkgs.rrsync} -ro /srv/matrix
  '';
in
{
  users.users.root.openssh.authorizedKeys.keys = [
    ''from="100.64.0.1/32",restrict,command="${restrictedRsync}" ${matrixBackupPubKey}''
  ];
}
