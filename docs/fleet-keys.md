# Fleet keys — inventory, rotation, revocation

Every SSH key and credential the fleet trusts, what it can do, and how to turn
it over. Read this before rotating anything.

## Why this document exists

Several of these keys are `trusted-users` on the Nix daemon, and one has
NOPASSWD sudo on every machine. A leaked key here is not an inconvenience, it
is root. The blast radius column is the only thing that makes the inventory
useful, so it is filled in from live state, not from intent.

## Inventory

| Key | Private half lives in | Trusted by | Privilege | Blast radius if leaked |
|---|---|---|---|---|
| `forgejo_runner_ssh_key` | sops secret, `systems-secrets/secrets/forgejo-ci-runner-vm.yaml` **only** | `nixdeploy` on **all 10 hosts** | nix `trusted-user` + **NOPASSWD sudo ALL** | **Total fleet compromise.** This is the crown jewel; nothing else comes close. |
| `fwai0_builder_ssh_key` | sops secret, `systems-secrets/secrets/dev-vm-xps.yaml` | `nixbuilder` on **fwai0 only** | nix `trusted-user`, **no sudo**, no interactive shell | Can queue builds on fwai0 and import store paths. Cannot read user data, activate configs, or reach any other host. |
| `tailscale-auth-key` | per-host sops secret | headscale (`homeserver`) | Can join a *new* node to the tailnet as that host | Rogue tailnet node; lateral pivot risk but not direct root. Rotate the single host's key. |
| sops age key (`~/.ssh/id_ed25519.age`) | admin workstation only, **not in the repo** | every `secrets/<host>.yaml` recipient list | Decrypts every host's secrets | All secrets at once. Guard this one like the deploy key. |
| syncoid replication key | **not in sops** — `/persist/secrets/syncoid-replication/id_ed25519_nop` on `pi-syncoid-target`, owned by user `syncoid` | `rramirez@homeserver` authorized_keys | ZFS read of `tank/data` | Backup data disclosure. Note it is a *no-passphrase* key sitting outside sops management. |
| host SSH keys | `/persist/etc/ssh/` on each host | peers' `known_hosts` | Server identity | Trust corruption; see `docs/host-addressing.md` for the pinned pins. |

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
3. **Workstation / age key compromised:** re-encrypt every `secrets/*.yaml` to a
   new age recipient set, then rotate every SSH key listed above, since all of
   them were readable.
4. After any revocation, run `scripts/check-sops-secrets.sh`.

## Known gap in the safety net

`scripts/check-sops-secrets.sh` **skips secrets that set `sopsFile`**. That is why
the fleet keeps one `secrets/<host>.yaml` per host instead of consolidating into
a shared file: consolidation would create a blind spot where CI stops validating
that a declared secret actually exists. If you ever add a `sopsFile`, remember
it is invisible to that check.
