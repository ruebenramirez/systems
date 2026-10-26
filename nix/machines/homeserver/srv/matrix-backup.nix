{ config, pkgs, tailnet, ... }:

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
      root@${tailnet.host "ssdnodes-1"}: \
      ${backupRoot}/
  '';

  # Freshness is judged by the source's proof-of-run marker, not by the age of
  # the backed-up data. An idle Matrix server legitimately produces unchanged
  # files, so mtime-based staleness would cry wolf; a missing or old marker means
  # the snapshot job itself stopped completing, which is the failure that
  # silently cost 16 days of backups in October 2026.
  freshness = pkgs.writeShellScript "matrix-backup-freshness" ''
    set -uo pipefail
    marker="${backupRoot}/.snapshot-success"
    maxAge=$(( 18 * 3600 ))   # source snapshots every 6h; tolerate three misses

    if [ ! -f "$marker" ]; then
      echo "FAIL: no snapshot marker at $marker; the source has never written one"
      exit 1
    fi

    now=$(${pkgs.coreutils}/bin/date +%s)
    mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$marker")
    age=$(( now - mtime ))
    echo "marker contents: $(cat "$marker")"
    echo "marker age: ''${age}s (limit ''${maxAge}s)"

    if [ "$age" -gt "$maxAge" ]; then
      echo "FAIL: newest source snapshot is ''${age}s old; matrix-snapshot on ssdnodes-1 is not completing"
      exit 1
    fi
    echo "OK: source snapshot is recent"
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

  # Deliberately a separate unit: a freshness alarm has to be able to fail loudly
  # without ever being in a position to skip a real backup run.
  systemd.services.matrix-backup-freshness = {
    description = "Verify the Matrix backup holds a recent source snapshot";
    after = [ "matrix-backup.service" ];
    unitConfig.ConditionPathIsMountPoint = "/tank";

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = freshness;
    };
  };

  systemd.timers.matrix-backup-freshness = {
    description = "Check Matrix backup freshness every six hours";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      # 45 min after the pull at 00/6:00
      OnCalendar = "*-*-* 00/6:45:00";
      Persistent = true;
      Unit = "matrix-backup-freshness.service";
    };
  };
}
