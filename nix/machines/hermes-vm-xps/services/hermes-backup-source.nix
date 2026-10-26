{ config, lib, pkgs, ... }:

let
  hermesBackupPubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIP/uzaQKIugRF7fXMXaCiubZCYiUVcwW3XqMgDBX7OG homeserver-hermes-backup";

  restrictedRsync = pkgs.writeShellScript "hermes-backup-source" ''
    exec ${lib.getExe pkgs.rrsync} -ro /srv/hermes
  '';

  snapshot = pkgs.writeShellScript "hermes-snapshot" ''
    set -euo pipefail
    src=/var/lib/hermes
    dst=/srv/hermes

    ${pkgs.coreutils}/bin/mkdir -p "$dst"

    # Consistent snapshots of the live SQLite DBs while the gateway may be writing.
    for db in state.db shared-state.db response_store.db runs_idempotency.db; do
      if [ -f "$src/$db" ]; then
        ${pkgs.sqlite}/bin/sqlite3 "$src/$db" ".backup '$dst/$db'"
      fi
    done

    # Everything else (skills, memories, sessions, config.yaml, .env, E2EE store, logs).
    ${pkgs.rsync}/bin/rsync -a --delete \
      --exclude '*.db' --exclude '*.db-shm' --exclude '*.db-wal' \
      "$src/" "$dst/"
  '';
in
{
  # The base ssh profile sets PermitRootLogin=no; the restricted backup key needs
  # forced-commands-only (mirrors hosted-sites-backup-source.nix).
  services.openssh.settings.PermitRootLogin = lib.mkForce "forced-commands-only";
  users.users.root.openssh.authorizedKeys.keys = [
    ''from="100.64.0.1/32",restrict,command="${restrictedRsync}" ${hermesBackupPubKey}''
  ];

  environment.systemPackages = [ pkgs.sqlite pkgs.rsync ];

  systemd.tmpfiles.rules = [
    "d /srv/hermes 0755 root root -"
  ];

  systemd.services.hermes-snapshot = {
    description = "Snapshot Hermes state into the rrsync export root";
    wants = [ "podman-hermes.service" ];
    after = [ "podman-hermes.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = snapshot;
    };
  };

  systemd.timers.hermes-snapshot = {
    description = "Snapshot Hermes state every six hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02/6:30:00";
      Persistent = true;
      Unit = "hermes-snapshot.service";
    };
  };
}
