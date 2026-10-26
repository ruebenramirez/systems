{ lib, pkgs, ... }:

let
  # Public half of `matrix_backup_ssh_private_key` (which lives in
  # secrets/homeserver.yaml); the homeserver pulls with the private half.
  matrixBackupPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIENp3iNbGOXCYwRbSa8j6J2dXPXdIo3e1uATXa1deSEn homeserver-matrix-backup";

  restrictedRsync = pkgs.writeShellScript "matrix-backup-source" ''
    exec ${lib.getExe pkgs.rrsync} -ro /srv/matrix
  '';
in
{
  users.users.root.openssh.authorizedKeys.keys = [
    ''from="100.64.0.1/32",restrict,command="${restrictedRsync}" ${matrixBackupPubKey}''
  ];
}
