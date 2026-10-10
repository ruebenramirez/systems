{ config, pkgs, ... }:

let
  backupRoot = "/tank/backups/ssdnodes-1/matrix";
  # rrsync (matrix-backup-source.nix) pins the remote root to /srv/matrix, so the
  # empty remote path below is that root.
  backup = pkgs.writeShellScript "matrix-backup" ''
    export RSYNC_RSH="${pkgs.openssh}/bin/ssh -F /dev/null -i ${config.sops.secrets.matrix_backup_ssh_private_key.path} -o BatchMode=yes -o ConnectTimeout=30 -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts -o IdentitiesOnly=yes -o ServerAliveCountMax=3 -o ServerAliveInterval=30 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/dev/null"

    exec ${pkgs.rsync}/bin/rsync \
      --archive \
      --delete-delay \
      --itemize-changes \
      --timeout=1800 \
      root@ssdnodes-1.tailnet.rueb.dev: \
      ${backupRoot}/
  '';
in
{
  sops.secrets.matrix_backup_ssh_private_key = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  users.groups.matrix-backup = { };
  users.users.rramirez.extraGroups = [ "matrix-backup" ];

  systemd.services.matrix-backup-directory = {
    description = "Create the Matrix backup directory";
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/tank";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.coreutils}/bin/install -d -m 2770 -o root -g matrix-backup ${backupRoot}
    '';
  };

  systemd.services.matrix-backup = {
    description = "Pull Matrix DB/media backups from ssdnodes-1";
    requires = [ "matrix-backup-directory.service" ];
    wants = [ "network-online.target" "tailscaled-autoconnect.service" ];
    after = [
      "matrix-backup-directory.service"
      "network-online.target"
      "tailscaled-autoconnect.service"
    ];
    unitConfig.ConditionPathIsMountPoint = "/tank";

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = backup;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ backupRoot ];
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      LockPersonality = true;
      RestrictRealtime = true;
    };
  };

  systemd.timers.matrix-backup = {
    description = "Pull Matrix backups every six hours";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "*-*-* 00/6:00:00";
      Persistent = true;
      Unit = "matrix-backup.service";
    };
  };
}
