# Fleet keys — inventory, rotation, revocation

Every SSH key and credential the fleet trusts, what it can do, and how to turn
it over. Read this before rotating anything.

## Why this document exists

Several of these keys are `trusted-users` on the Nix daemon, and one has
NOPASSWD sudo on every machine. A leaked key here is not an inconvenience, it
is root. The blast radius column is the only thing that makes the inventory
useful, so it is filled in from live state, not from intent.

Two of them deliberately live **outside sops**, because their private half has to
be usable by something that cannot decrypt sops (an agent container, a bare
replication target). Those are the ones to look at hardest: they are not covered
by `scripts/check-sops-secrets.sh` and nothing fails loudly if they drift.

## Inventory

| Key | Private half lives in | Trusted by | Privilege | Blast radius if leaked |
|---|---|---|---|---|
| `forgejo_runner_ssh_key` | sops secret, `systems-secrets/secrets/forgejo-ci-runner-vm.yaml` **only** | `nixdeploy` on **all 10 hosts** | nix `trusted-user` + **NOPASSWD sudo ALL** | **Total fleet compromise.** This is the crown jewel; nothing else comes close. |
| `fwai0_builder_ssh_key` | sops secret, `systems-secrets/secrets/dev-vm-xps.yaml` | `nixbuilder` on **fwai0 only** | nix `trusted-user`, **no sudo**, no interactive shell | Can queue builds on fwai0 and import store paths. Cannot read user data, activate configs, or reach any other host. |
| `tailscale-auth-key` | per-host sops secret | headscale (`homeserver`) | Can join a *new* node to the tailnet as that host | Rogue tailnet node; lateral pivot risk but not direct root. Rotate the single host's key. |
| sops age key (`~/.ssh/id_ed25519.age`) | admin workstation only, **not in the repo** | every `secrets/<host>.yaml` recipient list | Decrypts every host's secrets | All secrets at once. Guard this one like the deploy key. |
| syncoid replication key | **not in sops** — `/persist/secrets/syncoid-replication/id_ed25519_nop` on `pi-syncoid-target`, owned by user `syncoid` | `rramirez@homeserver` authorized_keys | ZFS read of `tank/data` | Backup data disclosure. Note it is a *no-passphrase* key sitting outside sops management. |
| `hermes` container key | **not in sops** — `/var/lib/hermes/.ssh/id_ed25519` on `hermes-vm-xps` (bind-mounted into the container as `~/.ssh`). Also copied into the homeserver backup by `hermes-backup-source.nix`. | `hermes` on **hermes-vm-xps only** | **NOPASSWD sudo ALL** on that VM | Root on `hermes-vm-xps`. The agent runs as root with `--network=host`, so a compromised agent already holds this key, and the backup set now holds it too. |
| host SSH keys | `/persist/etc/ssh/` on each host | peers' `known_hosts` | Server identity | Trust corruption; see `docs/host-addressing.md` for the pinned pins. |

> **Unverified claim in this table:** the `no interactive shell` column for
> `nixbuilder` (and the same `shell = pkgs.bashNonInteractive` used by
> `nixdeploy` and `hermes`) does not appear to hold. On `hermes-vm-xps`, all
> three resolve in `/etc/passwd` to `/run/current-system/sw/bin/bash`, which
> symlinks to `bash-interactive-5.3p9` — an interactive shell. The store path
> for `bashNonInteractive` is present in the closure but is not what the account
> gets. Treat "no interactive shell" as intent, not live state, until re-checked.

## Rotation procedures

### `forgejo_runner_ssh_key` (fleet deploy key)

Order matters — the new key must be trusted everywhere before the old one stops
working, or CI cannot deploy the fix that installs the new key.

1. Generate: `ssh-keygen -t ed25519 -N '' -C "forgejo-ci-runner-vm fleet deploy key" -f /tmp/new_deploy_key`
2. Update the public half in `nix/machines/_common/nix-deploy-user.nix`
   (`deployPubKey`).
3. Deploy **every host** so all of them trust the new key: `nup-fleet` (all
   machines). Do not skip any — the key is trusted on all ten.
4. Replace the private half in `systems-secrets/secrets/forgejo-ci-runner-vm.yaml`,
   commit, push, bump the `systems` flake lock, redeploy `forgejo-ci-runner-vm`.
5. Verify from the runner that the new key authenticates, then revoke the old
   key by redeploying (the `authorizedKeys` list is declarative, so the old key
   disappears on the next activation of each host).

### `fwai0_builder_ssh_key`

1. Generate a fresh ed25519 pair.
2. Update `builderPubKey` in `nix/machines/fwai0/services/nix-builder-access.nix`.
3. Deploy `fwai0`.
4. Replace the secret in `systems-secrets/secrets/dev-vm-xps.yaml`, push, bump
   the lock, deploy `dev-vm-xps`.
5. Verify the offload: on `dev-vm-xps`, an uncached unsigned `.drv` must print
   `building '...' on 'ssh-ng://nixbuilder@fwai0.tailnet.rueb.dev'`.

### `hermes` container key (`hermes-vm-xps`)

Deliberately **not in sops**: the private half has to be usable by the Hermes
agent container, which has no sops access, and `/var/lib/hermes` is the only
durable path in it (VM root disks are not backed up — see
`docs/incus-vm-management.md`). The trade is that the same directory is rsynced
into the homeserver backup, so the backup set holds a root credential for this
VM. To keep the key rebuildable-instead-of-backed-up instead, add
`--exclude '.ssh'` to the rsync in `nix/machines/hermes-vm-xps/services/hermes-backup-source.nix`.

1. Generate in place on the VM. The directory is bind-mounted into the container
   as `~/.ssh`, so writing it here is what the agent picks up:

   ```sh
   ssh hermes-vm-xps
   sudo install -d -m 0700 -o 10000 -g 10000 /var/lib/hermes/.ssh
   sudo ssh-keygen -t ed25519 -N '' -C hermes-container@hermes-vm-xps \
     -f /var/lib/hermes/.ssh/id_ed25519
   sudo chown 10000:10000 /var/lib/hermes/.ssh/id_ed25519*
   ```

   Never build this key in a Nix derivation: anything in the store is readable
   on the build host (`fwai0`) and is copied to the target in the clear.

2. Update the pubkey and the fingerprint comment in
   `nix/machines/hermes-vm-xps/configuration.nix`
   (`users.users.hermes.openssh.authorizedKeys.keys`).
3. `nup-fleet hermes-vm-xps`.
4. Verify from inside the container:

   ```sh
   sudo podman exec hermes ssh -o BatchMode=yes \
     hermes@hermes-vm-xps.tailnet.rueb.dev 'sudo -n id'
   ```

   Expect `uid=0(root)`.

The container's `HOME` is `/root`, so `~/.ssh` only resolves to this key because
`hermes-agent.nix` bind-mounts `/var/lib/hermes/.ssh` over `/root/.ssh`. If that
mount is ever dropped the agent silently goes back to writing keys into the
overlay, and they are destroyed on the next rebuild — which looks exactly like a
bad key.

### Editing sops files in this repo

`sops` in nixpkgs (3.13.3) does **not** expose a working `rm`/`set` edit
subcommand — `sops rm <file> <key>` parses `rm` as a filename and fails with a
misleading "no matching creation rules found". Do not hand-edit the YAML either:
the MAC covers the tree structure, so deleting a key by text edit makes the file
undecryptable.

The working procedure is decrypt → modify → re-encrypt **to the same recipients
already recorded in that file**:

```bash
export SOPS_AGE_KEY_FILE=~/.ssh/id_ed25519.age
sops -d secrets/HOST.yaml > plain.yaml          # edit plain.yaml
# recipients are in cleartext in the file's sops: block
recips=$(grep 'recipient: ' secrets/HOST.yaml | awk '{print $2}')
# re-encrypt from a directory whose .sops.yaml has a catch-all rule listing them
sops -e plain.yaml > secrets/HOST.yaml
```

Two traps: block scalars are re-indented to 4 spaces on re-encrypt, and sops
infers the format from the file extension, so writing to a non-`.yaml` name
silently produces JSON garbage.

Always verify after: the file decrypts, the intended key is gone or added, every
*other* value is byte-identical, and the recipient count is unchanged.

## Emergency revocation

If a key is compromised and you cannot rotate cleanly:

1. **Deploy key compromised:** remove `nixdeploy`'s `authorizedKeys` (or the whole
   `nix-deploy-user` import) and deploy. Because that needs the same channel CI
   uses, do it from a workstation with the sops age key, not from CI.
2. **Builder key compromised:** drop `nixbuilder`'s key from
   `nix-builder-access.nix`, deploy `fwai0`. Nothing else is affected — that is
   the point of the split.
3. **Hermes container key compromised:** drop the key from
   `users.users.hermes.openssh.authorizedKeys.keys` in
   `nix/machines/hermes-vm-xps/configuration.nix` and deploy `hermes-vm-xps`.
   This closes only the SSH path. The agent runs as root in the host network
   namespace, so if the agent itself is what got popped, assume the VM is gone —
   re-stage it rather than cleaning it.
4. **Workstation / age key compromised:** re-encrypt every `secrets/*.yaml` to a
   new age recipient set, then rotate every SSH key listed above, since all of
   them were readable.
5. After any revocation, run `scripts/check-sops-secrets.sh`.

## Known gap in the safety net

`scripts/check-sops-secrets.sh` **skips secrets that set `sopsFile`**. That is why
the fleet keeps one `secrets/<host>.yaml` per host instead of consolidating into
a shared file: consolidation would create a blind spot where CI stops validating
that a declared secret actually exists. If you ever add a `sopsFile`, remember
it is invisible to that check.
