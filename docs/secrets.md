# Secrets

How a secret gets from `systems-secrets` into a running process, how a change is
applied to a machine, and what to do when it does not arrive.

Authoring lives in the other repo: file naming, recipient lists, and why
revoking a key is a three-step operation are covered by
[`systems-secrets/CONVENTIONS.md`](https://code.rueb.dev/rueb/systems-secrets/src/branch/main/CONVENTIONS.md).
Credentials that deliberately live **outside** sops are in
[`docs/fleet-keys.md`](fleet-keys.md).

## How a secret reaches a process

```
systems-secrets commit
  → flake input revision (flake.lock)
  → encrypted file copied into the Nix store as part of the system closure
  → the activation script runs sops-install-secrets against the generated
    manifest.json (at deploy and again at boot)
  → /run/secrets/<name>, owned and modeled per declaration
  → service reads the path, or a sops template substitutes it into a config file
```

Two consequences worth internalising:

- **The encrypted file is in the store on every host that references it**, and on
  `fwai0`, which builds everything. Values stay encrypted; the access decision is
  the recipient list.
- **`/run/secrets/<name>` is keyed by the declaration's name, not the file it
  came from.** Renaming the file is invisible to consumers; renaming the
  declaration breaks every path reference (for example
  `_common/base/editor.nix` hardcodes `/run/secrets/openrouter-api-key`).

## The private `systems-secrets` input

`systems-secrets` is a **private** flake input fetched over `git+https://`, so
**git** authenticates it from the invoking user's `~/.netrc`. Nix's own
`netrc-file` setting does **not** cover `git+https://` inputs; it only applies
to Nix's own libcurl fetches.

| Host | How it gets the credential |
|------|----------------------------|
| `forgejo-ci-runner-vm` | Declaratively: the `forgejo_secrets_token` sops secret, rendered to `/var/lib/nixdeploy/.netrc` by [`nup-fleet-access.nix`](../nix/machines/forgejo-ci-runner-vm/services/nup-fleet-access.nix) |
| Every other machine (workstations included) | **Nothing.** `nup-fleet --upgrade` from a laptop stops at `Username for 'https://code.rueb.dev':` — git had nothing to offer and fell back to prompting. |

`nup-fleet` checks for a usable credential *before* `nix flake update` and
exports `GIT_TERMINAL_PROMPT=0`, so a missing token fails with a recipe instead
of hanging. `scripts/setup-forgejo-netrc.sh` installs one:

```bash
scripts/setup-forgejo-netrc.sh                              # prompt for a token
scripts/setup-forgejo-netrc.sh --from-runner forgejo-ci-runner-vm   # copy the runner's
scripts/setup-forgejo-netrc.sh --verify                     # test what is there
```

It writes a `machine code.rueb.dev` block to `~/.netrc` (mode 0600, backing up
the old file) and proves it by fetching the private repo's HEAD. By hand:

```text
machine code.rueb.dev
  login <forgejo-user>
  password <token>
```

Override the host with `PRIVATE_GIT_HOST` for a mirror or another Forgejo
instance. Deploying **without** `--upgrade` needs no credential, provided the
locked revision is already in the store: `nup-fleet homeserver`.

### The two credentials CI keeps apart

CI touches `code.rueb.dev` with two different credentials, and mixing them is a
failure mode waiting to happen:

| Who | Credential | Lifetime |
|-----|-----------|----------|
| `actions/checkout` (fetching `systems`, which is private) | the per-run task token (`secrets.GITHUB_TOKEN`) | the run |
| nix's git subprocesses (fetching `systems-secrets`) | `nixdeploy`'s netrc, i.e. `forgejo_secrets_token` | until it is rotated |

Both workflows blank the extraheader `actions/checkout` installs, at the workflow
level, so that nix's git sees the netrc instead. That blank outranks the header
checkout writes into the repo config, so the checkout steps un-blank it with
`GIT_CONFIG_COUNT: "0"`; left blanked, a checkout has no credential at all -- the
task token is discarded and checkout points git at a temporary `HOME`, away from
the netrc. See [CI](ci.md#checking-out-a-private-repo).

### Lockfile safety

A failed or interrupted update must not leave damage behind: on 2026-10-27 an
aborted run rewrote `flake.lock` with a *stale* `systems-secrets` rev while
exiting 1. `nix_flake_update` now keeps the pre-update lock and restores it on
any failure, and treats an input whose locked `lastModified` moves
**backwards** as a failure (the expired-cached-ref bug), so a half-moved lock
cannot ship older secret material.

## Declaring a secret

Every declaration names the file it comes from, through the `secretFile` helper
provided in `_module.args`:

```nix
sops.secrets.freshrss-pass = secretFile "freshrss-server-homeserver";

sops.secrets.smtp2go_password = secretFile "stalwart-server-homeserver" // {
  owner = "stalwart-mail";
  group = "stalwart-mail";
  mode = "0600";
  restartUnits = [ "stalwart.service" ];
};
```

`secretFile "x"` is just `{ sopsFile = "${systems-secrets}/secrets/<x>.yaml"; }`,
so `// { … }` merges the usual options alongside it.

There is deliberately **no** `sops.defaultSopsFile`. With one, a per-machine file
would keep being the implicit answer and access would quietly be
"whatever else that host can already read"; `_common/base/sops.nix` asserts that
every declaration names a file instead. A declaration that does not is an eval
error, not a runtime surprise:

```
These sops secrets do not name a sopsFile: some-key
Set one, e.g. sops.secrets.foo = secretFile "stalwart-server-homeserver";
```

`restartUnits` matters more than it looks: a secret read at `ExecStartPre` (sing-box
renders `/run/sing-box/config.json` at start) only picks up a rotated value when
the unit restarts.

## The map

Generated — do not edit by hand. Regenerate with
`scripts/sops-map.sh` and paste, or read it live:

```bash
scripts/sops-map.sh              # every file
scripts/sops-map.sh --no-hosts   # omit the ten single-consumer headscale rows
```

Each `headscale-client-<host>.yaml` holds that host's own `tailscale-auth-key`;
the ten values are distinct headscale pre-auth keys and must stay per-host.

<!-- BEGIN GENERATED: scripts/sops-map.sh --no-hosts -->
| file | keys | consumers | recipients |
|---|---|---|---|
| `cloudflare-dns-client.yaml` | `cloudflare-token` | homeserver ssdnodes-1 | admin homeserver ssdnodes-1 |
| `forgejo-client-forgejo-ci-runner-vm.yaml` | `forgejo_runner_token`, `forgejo_runner_uuid`, `forgejo_secrets_token` | forgejo-ci-runner-vm | admin forgejo-ci-runner-vm |
| `freshrss-server-homeserver.yaml` | `freshrss-pass` | homeserver | admin homeserver |
| `hermes-agent-server-hermes-vm-xps.yaml` | `hermes-api-server-key`, `hermes-dashboard-basic-auth-password`, `hermes-dashboard-basic-auth-secret`, `hermes-dashboard-basic-auth-username` | hermes-vm-xps | admin hermes-vm-xps |
| `hermes-backup-client-homeserver.yaml` | `hermes_backup_ssh_private_key` | homeserver | admin homeserver |
| `hosted-sites-backup-client-homeserver.yaml` | `hosted_sites_backup_ssh_private_key` | homeserver | admin homeserver |
| `matrix-backup-client-homeserver.yaml` | `matrix_backup_ssh_private_key` | homeserver | admin homeserver |
| `matrix-client-hermes-vm-xps.yaml` | `matrix-access-token`, `matrix-recovery-key` | hermes-vm-xps | admin hermes-vm-xps |
| `matrix-server-ssdnodes-1.yaml` | `matrix-admin-access-token` | ssdnodes-1 | admin ssdnodes-1 |
| `mullvad-client-download-vm-xps.yaml` | `wgnet_mullvad_conf` | download-vm-xps | admin download-vm-xps |
| `nix-builder-client-dev-vm-xps.yaml` | `fwai0_builder_ssh_key` | dev-vm-xps | admin dev-vm-xps |
| `nixdeploy-client-forgejo-ci-runner-vm.yaml` | `forgejo_runner_ssh_key` | forgejo-ci-runner-vm | admin forgejo-ci-runner-vm |
| `openrouter-client-forgejo-ci-runner-vm.yaml` | `openrouter-api-key` | forgejo-ci-runner-vm | admin dev-vm-xps driver forgejo-ci-runner-vm |
| `openrouter-client-hermes-vm-xps.yaml` | `openrouter-api-key` | hermes-vm-xps | admin hermes-vm-xps |
| `openrouter-client.yaml` | `openrouter-api-key` | dev-vm-xps driver | admin dev-vm-xps driver |
| `searx-server-homeserver.yaml` | `searx-secret-key` | homeserver | admin homeserver |
| `sing-box-client-driver.yaml` | `clash_api_secret`, `reality_public_key` | driver | admin driver |
| `sing-box-server-ssdnodes-1.yaml` | `reality_private_key` | ssdnodes-1 | admin ssdnodes-1 |
| `sing-box-shared.yaml` | `hy2_obfs_password`, `hy2_password`, `reality_short_id`, `vless_uuid` | driver ssdnodes-1 | admin driver ssdnodes-1 |
| `stalwart-server-homeserver.yaml` | `smtp2go_password`, `smtp2go_username`, `stalwart-api-key` | homeserver | admin homeserver |
| `webmail-server-homeserver.yaml` | `bulwark-admin-password`, `bulwark-session-secret` | homeserver | admin homeserver |
| `wireguard-client-homeserver.yaml` | `wgnet_home_conf` | homeserver | admin homeserver |

<!-- END GENERATED -->

`consumers` ⊆ `recipients` is the invariant. A consumer missing from recipients is
a host that will fail to decrypt at boot; a recipient missing from consumers is a
revocation that never finished. `check-sops-secrets.sh` fails the build on the
first; the second is what the periodic audit looks for.

## Validating before you deploy

```bash
scripts/check-sops-secrets.sh            # every host
scripts/check-sops-secrets.sh driver     # one host
nup-fleet check --no-build driver        # does it evaluate
nup-fleet check driver                   # does it build (on fwai0)
```

`check-sops-secrets.sh` proves, for every declaration:

1. the named file exists in the locked `systems-secrets` revision;
2. that file contains the key;
3. **this host is a recipient of that file** — sops decrypts per file, so a
   missing recipient is a boot failure on a machine that may be nowhere near you.

It decrypts nothing: sops leaves key names and recipient lists in cleartext, so it
runs unprivileged in CI. Blocking findings exit 1 (missing file, missing key,
missing recipient, a config that will not evaluate); orphans — a key no host
declares, a file nothing references — warn only. A hygiene finding must never
leave the fleet unpatched overnight.

Locally the check reads the *committed* lock; CI runs
`nup-fleet --flake-update-only` first so it judges against the revisions the
deploy is about to use. The credential is described in
[The private `systems-secrets` input](#the-private-systems-secrets-input).

## Applying a change to a machine

`nup-fleet` is the only supported path. It builds on `fwai0` and switches over
ssh; ad-hoc `nixos-rebuild --target-host`, `nix deploy`, and manual `nix copy` +
`switch` all skip the lock and credential handling it does.

```bash
nup-fleet --upgrade driver          # nix flake update, then deploy
nup-fleet driver                    # deploy at the current lock
nup-fleet --flake-update-only       # re-lock only
nup-fleet check driver              # validate, deploy nothing
nup-fleet rollback driver           # back to the previous generation
```

For a batch, prefer one lock: `nup-fleet --flake-update-only` once, commit
`flake.lock`, then deploy each host without `--upgrade`. Running `--upgrade` per
host re-runs `nix flake update` each time, so a two-host batch produces two
different locks and a mid-batch failure leaves the fleet split between them.

**A secret is only rotated once it reaches the host.** The chain that has to work:

1. Commit the re-encrypted file to `systems-secrets` and push.
2. Re-lock `systems` (CI's `nix flake update`, or `nix flake update systems-secrets`
   by hand). Skip this and the host gets the **old** locked revision, which looks
   exactly like a failed rotation.
3. Deploy. The evaluation happens on the machine running `nixos-rebuild`, which
   copies the closure to the build host, so `fwai0` needs no credentials for the
   secrets repo — it only sees the `.drv`.

And a value change is not the same as an access change: rotating a
`tailscale-auth-key` is meaningless unless the old key is revoked in headscale,
because a running host never re-reads it.

## When a secret does not arrive

`nup-fleet` printing `✓` does **not** mean the secrets are healthy — verify the
files themselves:

```bash
ssh <host> 'sudo ls -l /run/secrets'            # every declared name present
ssh <host> 'sudo cat /run/secrets/<name>'       # compare against `sops -d` on the source
ssh <host> 'systemctl --failed'
```

**Do not use the `sops-install-secrets.service` unit as a health signal** — it
never runs as a unit; see
[Alerting](alerting.md#the-sops-install-secrets-unit-is-not-a-health-signal).
Use the file comparison above.

| symptom | cause |
|---|---|
| `failed to fetch key` / `no identity matched` | host's age key changed, or the host is not a recipient. Compare `grep 'recipient: ' <file>` against the host's key; `sops` prints a wall of failures rather than naming this cause |
| `Could not find key <name> in <file>` | declaration names a key the file does not have — `check-sops-secrets.sh` would have caught it |
| activation fails with a sops error | the file or key is missing in the locked revision, or the host cannot decrypt it; `check-sops-secrets.sh` predicts exactly this |
| secret absent, activation succeeded | wrong `sopsFile` (a file the host *can* read but that lacks the key cannot happen — the key must exist for activation to pass), or the consumer caches the old value: check `restartUnits` and whether the consumer reads at `ExecStartPre` |
| `LoadState=bad-setting` on `sops-install-secrets.service` | expected; see the note above |

`nixos-rebuild switch` applies changes incrementally and does not undo itself, so
recovery is explicit: `nup-fleet rollback <host>` switches the machine back to the
generation it was on before the last deploy. Check `nixos-rebuild
list-generations --target-host <host>` first if you need to know what you are
returning to.

## Keys that expire on their own

All ten headscale pre-auth keys expire **2027-10-26** (minted with `-e 8760h`).
Re-mint before then: `sudo headscale preauthkeys create -u 1 -e 8760h -o json` on
`homeserver`, capture the returned `id`, update that host's
`headscale-client-<host>.yaml`, and revoke the old key in headscale. Keys are
non-reusable, so a burned key needs a fresh mint, not a retry.

## If plaintext touched an agent session

Never paste secret values into chat or commit them. If a session's transcript
holds plaintext, delete the session file once the rotation is confirmed landed,
and record that you did: an agent cannot carry a reminder into a future session,
so the repo is the only place that note survives.

## See also

- [`docs/fleet-keys.md`](fleet-keys.md) — SSH keys and out-of-sops credentials,
  rotation procedures, emergency revocation.
- [`systems-secrets/CONVENTIONS.md`](https://code.rueb.dev/rueb/systems-secrets/src/branch/main/CONVENTIONS.md)
  — layout, recipient model, the three-step revocation procedure.
