{ config, lib, pkgs, secretFile, ... }:

let
  # Where the restricted rrsync source (matrix-backup-source.nix) exposes the
  # export to the homeserver pull.
  exportRoot = "/srv/matrix";

  # Admin room id, captured at bootstrap (Phase 1c). Created on the guest.
  adminRoomFile = "/var/lib/matrix-backup/admin-room-id";

  apiBase = "http://127.0.0.1:6167";

  snapshot = pkgs.writeShellScript "matrix-snapshot" ''
    set -euo pipefail

    token="$(cat ${config.sops.secrets.matrix-admin-access-token.path})"

    # Trigger continuwuity's online RocksDB backup via the admin room. A refused
    # trigger costs the new checkpoint, not the publish: the media mirror and the
    # last good checkpoint are still worth shipping, and aborting here is what
    # turned a dead admin token into a full backup outage (issue #1088). The
    # degradation is recorded beside the run marker so the homeserver's freshness
    # check fails loudly instead of blessing a stale checkpoint.
    degraded=""
    if [ ! -f ${adminRoomFile} ]; then
      degraded="admin room id missing at ${adminRoomFile}"
    else
      room="$(cat ${adminRoomFile})"
      txn="backup-$(date +%s)"
      if ${pkgs.curl}/bin/curl -fsS -o /dev/null -X PUT \
        "${apiBase}/_matrix/client/v3/rooms/''${room}/send/m.room.message/''${txn}" \
        -H "Authorization: Bearer ''${token}" \
        -H "Content-Type: application/json" \
        -d '{"msgtype":"m.text","body":"!admin server backup-database"}'
      then
        # Let the server finish writing the checkpoint before we copy it.
        sleep 20
      else
        degraded="admin backup trigger rejected; the access token or the admin room is broken"
      fi
    fi

    dbBackups=/var/lib/continuwuity/db-backups
    media=/var/lib/continuwuity/media

    ${pkgs.rsync}/bin/rsync -a --delete "''${media}/" ${exportRoot}/media/

    # Continuwuity's RocksDB online backup is a structured tree
    # (meta/ private/ shared_checksum/), so mirror the whole thing.
    ${pkgs.rsync}/bin/rsync -a --delete "''${dbBackups}/" ${exportRoot}/db-backup/

    # Proof-of-run marker, pulled along by the homeserver's rsync. This records
    # that a snapshot actually completed, which a data mtime cannot: an idle
    # Matrix server legitimately produces unchanged data, so "nothing changed"
    # is not evidence of breakage and "something is new" is not evidence of
    # health. Only a run marker distinguishes the two.
    ${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ > ${exportRoot}/.snapshot-success

    # Second marker: the mirror completed but carried no fresh checkpoint. It
    # rides out with the same rsync, and the homeserver's freshness check fails on
    # it; a healthy run removes it, so its absence means something.
    if [ -n "''${degraded}" ]; then
      printf '%s\n' "''${degraded}" > ${exportRoot}/.snapshot-degraded
      echo "WARN: mirrored without a new database checkpoint: ''${degraded}" >&2
    else
      ${pkgs.coreutils}/bin/rm -f ${exportRoot}/.snapshot-degraded
    fi
  '';
in
{
  # @r3v2 access token, used to send `!admin` commands to the admin room.
  sops.secrets.matrix-admin-access-token = secretFile "matrix-server-ssdnodes-1" // {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d ${exportRoot} 0755 root root -"
    "d /var/lib/matrix-backup 0700 root root -"
  ];

  systemd.services.matrix-snapshot = {
    description = "Snapshot Matrix DB/media into the rrsync export root";
    wants = [ "continuwuity.service" ];
    after = [ "continuwuity.service" "sops-install-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = snapshot;
    };
  };

  systemd.timers.matrix-snapshot = {
    description = "Snapshot Matrix DB/media every six hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05/6:30:00";
      Persistent = true;
      Unit = "matrix-snapshot.service";
    };
  };
}
