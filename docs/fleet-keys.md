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
| `forgejo_runner_ssh_key` | sops secret, `systems-secrets/secrets/nixdeploy-client-forgejo-ci-runner-vm.yaml` **only** | `nixdeploy` on **all 10 hosts** | nix `trusted-user` + **NOPASSWD sudo ALL** | **Total fleet compromise.** This is the crown jewel; nothing else comes close. |
| `fwai0_builder_ssh_key` | sops secret, `systems-secrets/secrets/nix-builder-client-dev-vm-xps.yaml` | `nixbuilder` on **fwai0 only** | nix `trusted-user`, **no sudo**, no interactive shell | Can queue builds on fwai0 and import store paths. Cannot read user data, activate configs, or reach any other host. |
| `tailscale-auth-key` | one sops file per host (`headscale-client-<host>.yaml`); the ten values are distinct | headscale (`homeserver`) | Can join a *new* node to the tailnet as that host | One node, one host, expiring. Rogue tailnet node; lateral pivot risk but not direct root. Rotate that host's key. |
| sops age key (`~/.ssh/id_ed25519.age`) | admin workstation only, **not in the repo**; backup copy in 1Password | every file's recipient list | Decrypts every host's secrets | All secrets at once. Guard this one like the deploy key. |
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
4. Replace the private half in `systems-secrets/secrets/nixdeploy-client-forgejo-ci-runner-vm.yaml`,
   commit, push, bump the `systems` flake lock, redeploy `forgejo-ci-runner-vm`.
5. Verify from the runner that the new key authenticates, then revoke the old
   key by redeploying (the `authorizedKeys` list is declarative, so the old key
   disappears on the next activation of each host).

### `fwai0_builder_ssh_key`

1. Generate a fresh ed25519 pair.
2. Update `builderPubKey` in `nix/machines/fwai0/services/nix-builder-access.nix`.
3. Deploy `fwai0`.
4. Replace the secret in `systems-secrets/secrets/nix-builder-client-dev-vm-xps.yaml`,
   push, bump the lock, deploy `dev-vm-xps`.
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

### Editing sops files

`sops` in nixpkgs (3.13.3) has no working edit subcommand — verified:
`sops rm f.yaml k` fails with a misleading *"no matching creation rules found"*
even when a rule matches, and `sops set f.yaml k v` fails with *"Invalid set index
format"*. Do not hand-edit the YAML either: the MAC covers the whole tree, so
deleting a key by text edit makes the file undecryptable.

The working procedure is decrypt → modify → re-encrypt **in place at the file's
real path**, so `.sops.yaml` picks the recipients for that path:

```bash
export SOPS_AGE_KEY_FILE=~/.ssh/id_ed25519.age
sops -d secrets/<file>.yaml > /tmp/<file>.yaml      # edit /tmp/<file>.yaml
cp /tmp/<file>.yaml secrets/<file>.yaml
sops -e -i secrets/<file>.yaml
```

The trap that bites: `sops -e plain.yaml > secrets/<file>.yaml` chooses the
creation rule from the **input** path, so it encrypts to the wrong recipients and
reports success.

Two more: block scalars are re-indented on re-encrypt, and sops takes the format
from the file extension, so writing to a non-`.yaml` name silently produces JSON.

Always verify after: the file decrypts, the intended key is gone or added, every
*other* value is byte-identical, and `sops updatekeys -y` says
`already up to date` while leaving the tree clean.

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
4. **Workstation / age key compromised:** this is a revocation, not a re-encrypt,
   and it takes three ordered steps (see
   [`systems-secrets/CONVENTIONS.md`](https://code.rueb.dev/rueb/systems-secrets/src/branch/main/CONVENTIONS.md)):
   remove the key from `.sops.yaml`; `sops updatekeys` **then**
   `sops rotate --in-place` on every affected file, in that order; only then
   rotate the credentials themselves. `updatekeys` alone re-wraps the same data
   key, so a party that could read the file before can still read it after — and
   every historical revision in git remains decryptable with the old key. Assume
   every SSH key listed above was readable, since all of them were.
5. After any revocation, run `scripts/check-sops-secrets.sh`.

## headscale pre-auth keys

Each host holds its own non-reusable pre-auth key (`headscale-client-<host>.yaml`,
headscale ids 16–25, minted with `-e 8760h`, all expiring **2027-10-26**).

Mint (on `homeserver`):

```sh
sudo headscale preauthkeys create -u 1 -e 8760h -o json
```

**Capture the `id` from that output.** It is the only reliable handle for the key
later: `headscale preauthkeys list` masks the key value
(`hskey-auth-XXXX***********`), so a created key can never be matched to a
`list` row by value. Every ten hosts once shared one reusable key with a
~156-year expiry, which made any single leak equivalent to unlimited permanent
node enrollment as `rueb`.

Revoke: `sudo headscale preauthkeys expire --id <n>` (or `delete`). Rotating the
sops value without revoking in headscale changes nothing about what headscale
accepts. Expiring is not the same as proving — verify capability, e.g. start a
throwaway `tailscaled` with its own state file and `--tun=userspace-networking`
(so it cannot disturb the live tunnel) and confirm the old key is refused.

A running host never re-reads its key: `tailscaled-autoconnect` runs
`tailscale up --auth-key` only in `NeedsLogin` / `NeedsMachineAuth` / `Stopped`, so
rotation cannot break an enrolled host — and node keys are independent of pre-auth
keys, so expiring one never displaces a live node.

Two rules earned the hard way during the October 2026 rotation:

1. Never drive a destroy loop from a comparison whose failure mode is silent
   non-matching. A loop that expired "everything that didn't match a host key"
   expired all ten host keys, because masking made every comparison fail.
   Assert that something matched before destroying anything.
2. `tailscale up` echoes the auth key in its error output. Redact anything that
   captures a failed re-auth.

## Rotation ground rules

Standing rules, from the October 2026 fleet rotation:

1. **Research before rotate.** For each credential, record what it is (format,
   issuer, scope), how the dependent service consumes it (path, env var,
   `LoadCredential`, one-shot vs long-lived, cached in a database?), what rotation
   breaks and in what order, and how to verify success without waiting for a
   scheduled job. No rotation runs before that is written down.
2. **Recent rotation is not a skip condition.**
3. **Rotate the pair, not the half.** Where a public half is committed here, both
   halves land in the same change.
4. **Never hand-edit a sops file** — see above.

## Pending rotation

`forgejo_secrets_token` (the runner's read-only Forgejo token for this private
repo) was left unrotated in the October 2026 pass. It is scoped with more than
read access to `systems-secrets`; rotating it means generating a new token in
Forgejo, updating `secrets/forgejo-client-forgejo-ci-runner-vm.yaml`, and
redeploying `forgejo-ci-runner-vm`.

## Credentials with no declarative home

Outside sops, outside this repo's reach, and therefore invisible to
`check-sops-secrets.sh` — each is a rotation that has to be remembered by hand:

| Where | What | Status |
|---|---|---|
| `pi-syncoid-target:/persist/secrets/syncoid-replication/id_ed25519_nop` | no-passphrase ZFS replication key | documented gap; move into sops |
| `homeserver:/persist/secrets/mailsync/accounts.json` | Gmail app passwords + Stalwart creds, read every minute | tracked in rueb/systems#32 |
| `ssdnodes-1` WordPress containers (`:8011`, `:8012`) | `wp-config.php` DB password + auth salts | no declarative home at all |
| headscale SQLite (`/var/lib/headscale`) | node keys, pre-auth key set | rotate via the `headscale` CLI, not sops |
| `openrouter-client-homeserver.yaml` | OpenRouter key used by OpenWebUI | in sops but declared by nothing: `check-sops-secrets.sh` warns on it, and OpenWebUI holds its own copy — rotate in the OpenRouter dashboard and update both |

The last row is a different failure mode from the rest: the credential is
encrypted with the right recipients, but no `sops.secrets` entry reads it, so no
host ever decrypts it. The file exists to stop the value being lost, not to
deliver it; a rotation has to be done in the dashboard *and* in the file.

## See also

- [`docs/secrets.md`](secrets.md) — how a secret reaches a host, how changes are
  applied and rolled back, and the CI check that gates them.
- [`systems-secrets/CONVENTIONS.md`](https://code.rueb.dev/rueb/systems-secrets/src/branch/main/CONVENTIONS.md)
  — recipient model and the revocation procedure.
