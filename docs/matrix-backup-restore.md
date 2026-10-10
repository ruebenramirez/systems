# Matrix (Continuwuity) backup & restore

Continuwuity runs on `ssdnodes-1` as `matrix.rueb.dev`. Its RocksDB state and
media are backed up every six hours and pulled to the homeserver `tank`.

## Pipeline

1. **ssdnodes-1 `matrix-snapshot.timer`** (every 6h, `05/6:30`):
   - sends `!admin server backup-database` to the admin room via the client API,
     using `matrix-admin-access-token` (the `@r3v2` token) and the room id in
     `/var/lib/matrix-backup/admin-room-id`;
   - waits 20 s for the checkpoint to finish;
   - mirrors `/var/lib/continuwuity/media` → `/srv/matrix/media`;
   - mirrors `/var/lib/continuwuity/db-backups` → `/srv/matrix/db-backup`.
2. **ssdnodes-1 `matrix-backup-source.nix`** exposes `/srv/matrix` read-only over
   the tailnet via `rrsync` to the `homeserver-matrix-backup` key
   (`from="100.64.0.1/32"`).
3. **homeserver `matrix-backup.timer`** (every 6h, `00/6:00`) pulls
   `root@ssdnodes-1.tailnet.rueb.dev:` → `/tank/backups/ssdnodes-1/matrix/`
   (media + db-backup), which Sanoid snapshots and `syncoid` ships to
   `pi-syncoid-target`.

## Backup layout

`!admin server backup-database` writes a numbered checkpoint under
`database_backup_path` (`/var/lib/continuwuity/db-backups`):

```
db-backups/
  meta/<n>                    # ASCII manifest: timestamp + one line per SST
                              #   shared_checksum/<num>_<uuid>_<size>.sst crc32 <crc>
  private/<n>/{CURRENT,MANIFEST-*,OPTIONS-*,*.log}   # RocksDB checkpoint dir
  shared_checksum/<...>.sst   # content-deduplicated SST files (shared across backups)
```

`<n>` increments per backup (`!admin server list-backups` lists them). SST files
are shared content-addressed between backups; the manifest maps the RocksDB file
numbers to their `shared_checksum` names.

## Restore

> The exact recovery step is **not yet exposed as an admin command in
> Continuwuity 26.9.1** (only `backup-database`/`list-backups` exist). Do not
> treat a restore as validated until the drill below passes. Run the drill after
> any Continuwuity version bump.

The backup must be restored **as a whole tree** (`meta/`, `private/`,
`shared_checksum/`) — the checkpoint's MANIFEST references SSTs by the
`shared_checksum` names, so copying `private/<n>` alone is not enough.

### Drill (do this on a throwaway host/container, never in place first)

1. Pick the newest backup `<n>` (`!admin server list-backups`).
2. Copy the backup tree from the homeserver mirror:
   `rsync -a homeserver:/tank/backups/ssdnodes-1/matrix/db-backup/ /tmp/restore/db-backup/`
   (and `.../media/` if needed).
3. Start a **throwaway** Continuwuity of the **same version** (26.9.1) with:
   - `database_path` → a fresh empty dir,
   - `database_backup_path` → `/tmp/restore/db-backup`,
   - federation/registration disabled.
   Determine whether it auto-recovers from `<n>`, or consult upstream docs
   (`https://continuwuity.org/`) for the recovery command, and record the exact
   steps here once confirmed.
4. Verify against the live server: log in as a known user, read a known room,
   confirm message history and media resolve.

### In-place restore (only after the drill is proven)

1. Stop the service: `systemctl stop continuwuity matrix-snapshot.timer`.
2. Back up the current state dir: `mv /var/lib/continuwuity /var/lib/continuwuity.bad`.
3. Recreate the state dir and restore the verified backup tree + media from
   `/tank/backups/ssdnodes-1/matrix/`.
4. Restart and verify (`!admin server list-backups`, client login, a room read).
5. Resume `matrix-snapshot.timer`.

## Retention

Latest mirror on `tank` + Sanoid snapshots (`tank/data`) + `syncoid` replicas on
`pi-syncoid-target`. Old numbered checkpoints accumulate under `db-backups/`;
prune them on the source (or rely on the tank mirror's snapshot retention) once
the drill confirms only the newest is needed.

## Manual trigger

```sh
ssh ssdnodes-1 'sudo systemctl start matrix-snapshot.service'
ssh homeserver 'sudo systemctl start matrix-backup.service'
```
