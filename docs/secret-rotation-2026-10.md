# Secret rotation — October 2026

Started 2026-10-26. Trigger: fleet config and secret material passed through
third-party hosted LLMs during recent work. Secret *values* are age-encrypted
and were never exposed, but secret **names**, age **recipients**, and every
**public key committed in this repo** were. Rotation is therefore policy-driven,
not incident-driven.

## Standing rules

1. **Research before rotate.** For every secret, establish and record:
   - what the credential *is* (format, issuer, scope);
   - how the dependent service consumes it (file path, env var, `LoadCredential`,
     one-shot vs. long-lived, cached in a DB?);
   - what rotation breaks, and in which order it must happen;
   - how to verify success without waiting for a scheduled job.
   No rotation is executed before this is written down.
2. **Recent rotation is not a skip condition.** Anything in scope gets rotated
   again today.
3. **Rotate the pair, not the half.** Where a public half is committed in this
   repo, the new public half and the new private half land in the same change.
4. **Never hand-edit a sops file.** Decrypt → edit → re-encrypt to the recipients
   already recorded in that file (see `docs/fleet-keys.md`). Verify: decrypts,
   intended key changed, every *other* value byte-identical, recipient count
   unchanged.

## Baseline (2026-10-26)

- `scripts/check-sops-secrets.sh` — all 10 hosts `OK`.
- Reverse scan (keys in sops with no `sops.secrets` declaration) — 3 orphans,
  listed below.
- `flake.lock` pins `systems-secrets@b11943fb`.
- All 8 ACME certificates healthy (46–82 days out); no ACME failures in 14 days.

### Correction logged for the record

An earlier claim that both Cloudflare API tokens were revoked was **wrong**.
They are *account-owned* tokens (`cfat_` prefix) and must be verified with
`GET /accounts/{account_id}/tokens/verify`; `GET /user/tokens/verify` returns
error 1000 for them regardless of validity. Correct endpoint returns
`"This API Token is valid and active"`. A consistently wrong test yields
consistent false negatives, not corroboration.

## Inventory

Exposure: **public** = reachable from the internet · **tailnet** = overlay only ·
**lan** = NAT-protected home network · **local** = on-host only.

### `secrets/ssdnodes-1.yaml` — public VPS

| Secret | Service / consumer | Exposure | Rotation notes |
|---|---|---|---|
| `vless_uuid` | sing-box `vless-in` (server) **and** `_common/sing-box-client.nix` (driver) | public TCP 443 via HAProxy SNI | server+client must change atomically |
| `reality_private_key` | sing-box Reality (server) | public | paired with `reality_public_key` on driver |
| `reality_short_id` | sing-box Reality (server **and** driver) | public | shared value |
| `hy2_password` | sing-box Hysteria2 (server **and** driver) | public UDP 443 | shared value |
| `hy2_obfs_password` | sing-box Hysteria2 obfs (server **and** driver) | public UDP 443 | shared value |
| `matrix-admin-access-token` | `srv/matrix-snapshot.nix` → `!admin` commands in the admin room | local (loopback API) | Matrix access token; revocable per-token |
| `tailscale-auth-key` | `_common/tailscale-client.nix` → headscale enrollment | public host | headscale pre-auth key, single-use |
| `cloudflare-token` | both `*-reverse-proxy.nix` ACME DNS-01 | public | **migrated from `/persist/secrets` plaintext 2026-10-26** |
| ~~`continuwuity-registration-token`~~ | **ORPHAN** — nothing declares it; `allow_registration = false` | — | delete |
| ~~`matrix_backup_ssh_private_key`~~ | **ORPHAN** — only the *public* half is used here (`matrix-backup-source.nix`) | — | delete |

### `secrets/homeserver.yaml` — headscale is public; rest is tailnet/lan

| Secret | Service / consumer | Exposure | Rotation notes |
|---|---|---|---|
| `tailscale-auth-key` | headscale's own tailscaled | public host | pre-auth key |
| `cloudflare-token` | `acme-wildcard.nix` → `*.rueb.dev`, `*.monicaandrueben.com`, `*.monicarosephotography.com` | public (trust path) | **different token** from the VPS one; issues the cert `hs.rueb.dev` presents |
| `smtp2go_username` / `smtp2go_password` | Stalwart outbound relay via `LoadCredential` | tailnet | third-party: rotate at SMTP2GO first |
| `freshrss-pass` | FreshRSS `passwordFile` | tailnet | admin password |
| `searx-secret-key` | SearXNG `environmentFile` | tailnet | Flask secret key; rotating invalidates sessions |
| `bulwark-admin-password` / `bulwark-session-secret` | Bulwark webmail `environmentFiles` | tailnet | session secret rotation logs everyone out |
| `openrouter-api-key` | Open WebUI (dummy slot; endpoint is unauthenticated halogen) | tailnet | third-party |
| `matrix_backup_ssh_private_key` | `srv/matrix-backup.nix` rrsync pull from **public VPS** | tailnet→public pivot | public half in `ssdnodes-1/srv/matrix-backup-source.nix` |
| `hosted_sites_backup_ssh_private_key` | `srv/hosted-sites-backup.nix` rrsync pull from **public VPS** | tailnet→public pivot | public half in `ssdnodes-1/srv/hosted-sites-backup-source.nix` |
| `hermes_backup_ssh_private_key` | `srv/hermes-backup.nix` rrsync pull from hermes-vm-xps | tailnet | public half in `hermes-vm-xps/services/hermes-backup-source.nix` |
| `wgnet_home_conf` | `_common/home-vpn-client.nix` `wg0` | lan | legacy wgnet |
| ~~`matrix_backup_ssh_public_key`~~ | **ORPHAN** — public halves are committed in this repo, not read from sops | — | delete |

### Other hosts

| File | Secret | Consumer | Exposure |
|---|---|---|---|
| `forgejo-ci-runner-vm.yaml` | `forgejo_runner_ssh_key` | `nup-fleet-access.nix` → `nixdeploy` = trusted-user + NOPASSWD ALL on **all 10 hosts** | **crown jewel** |
| | `forgejo_runner_token` / `forgejo_runner_uuid` | `forgejo-runner.nix` runner registration | tailnet |
| | `forgejo_secrets_token` | netrc letting `nix` fetch the private `systems-secrets` repo | tailnet |
| | `openrouter-api-key` | `_common/dev.nix` agent tooling | local |
| | `tailscale-auth-key` | tailscaled | tailnet |
| `driver.yaml` | `vless_uuid`, `reality_public_key`, `reality_short_id`, `hy2_password`, `hy2_obfs_password` | `_common/sing-box-client.nix` | client half of the public proxy |
| | `clash_api_secret` | sing-box local Clash API | local (127.0.0.1) |
| | `openrouter-api-key`, `tailscale-auth-key` | dev.nix / tailscaled | local / tailnet |
| `dev-vm-xps.yaml` | `fwai0_builder_ssh_key` | `remote-builder-fwai0.nix` → `nixbuilder` on fwai0 (trusted-user, no sudo) | tailnet |
| | `openrouter-api-key`, `tailscale-auth-key` | dev.nix / tailscaled | local / tailnet |
| `hermes-vm-xps.yaml` | `hermes-dashboard-basic-auth-{username,password,secret}` | `hermes-agent.nix` managed config | tailnet |
| | `hermes-api-server-key` | Hermes API server auth | tailnet |
| | `matrix-access-token`, `matrix-recovery-key` | Hermes Matrix bridge (E2EE) | tailnet |
| | `openrouter-api-key`, `tailscale-auth-key` | dev tooling / tailscaled | local / tailnet |
| `download-vm-xps.yaml` | `wgnet_mullvad_conf` | `_common/mullvad-vpn-client.nix` `wg1` (tailnet exit node egress) | tailnet egress |
| | `tailscale-auth-key` | tailscaled (exit node) | tailnet |
| `fwai0.yaml`, `xps17.yaml`, `pi-syncoid-target.yaml` | `tailscale-auth-key` | tailscaled | tailnet |

## Shared-value secrets — rotate once, update N files

| Value | Files | Deploy set |
|---|---|---|
| `tailscale-auth-key` | all 10 | every host (per-host distinct key, one headscale pre-auth each) |
| `openrouter-api-key` | homeserver, driver, dev-vm-xps, forgejo-ci-runner-vm, hermes-vm-xps | 5 hosts |
| sing-box client/server pair | `ssdnodes-1.yaml` + `driver.yaml` | ssdnodes-1 then driver, same change |
| `reality_private_key` ↔ `reality_public_key` | `ssdnodes-1.yaml` ↔ `driver.yaml` | atomic |
| `cloudflare-token` | homeserver **and** ssdnodes-1 — **two distinct tokens** | rotate independently |

## Credentials outside sops (in scope)

| Location | What | Status |
|---|---|---|
| `pi-syncoid-target:/persist/secrets/syncoid-replication/id_ed25519_nop` | no-passphrase ZFS replication key | documented gap; move into sops |
| `homeserver:/persist/secrets/mailsync/accounts.json` | Gmail app passwords + Stalwart creds, read every minute | move into sops |
| `ssdnodes-1` WordPress containers (`:8011`, `:8012`) | `wp-config.php` DB password + auth salts | no declarative home at all |
| headscale SQLite (`/var/lib/headscale`) | node keys, pre-auth key set | not sops; rotate via `headscale` CLI |

## Research notes

### R1 — sing-box stealth proxy (`ssdnodes-1` server + `driver` client)

*What each credential is*

| Secret | Format | Issued by |
|---|---|---|
| `vless_uuid` | UUIDv4, VLESS user id | `uuidgen` |
| `reality_private_key` | X25519 private key (server half) | `sing-box generate reality-keypair` |
| `reality_public_key` | X25519 public key (client half, in `driver.yaml`) | same command, paired |
| `reality_short_id` | ≤8 bytes of hex, server accepts a list | arbitrary, `openssl rand -hex 8` |
| `hy2_password` | arbitrary string, Hysteria2 user auth | `openssl rand -hex 32` |
| `hy2_obfs_password` | arbitrary string, `salamander` obfs layer | `openssl rand -hex 32` |
| `clash_api_secret` | bearer secret for sing-box Clash API on `127.0.0.1:9090` | arbitrary; `driver` only, local |

*How the service consumes them — the important part*

The NixOS `sing-box` module does **not** pass these to sing-box as credentials.
Its `_secret` support is an `ExecStartPre` script that shells each
`/run/secrets/<name>` into an env var and `jq`-substitutes the **plaintext
values** into a rendered `/run/sing-box/config.json`:

```
secret1=$(<'/run/secrets/reality_private_key'); export secret1
...
jq '."inbounds"[0]."tls"."reality"."private_key" = ($ENV.secret1) | ...' \
   > /run/sing-box/config.json
```

The render happens **only when the unit starts**. Neither
`srv/sing-box.nix` nor `_common/sing-box-client.nix` declares `restartUnits`,
so sops-nix will **not** restart `sing-box` when the secret value changes.

**Consequence:** rotating these secrets and running `nup-fleet` leaves the
running process on the **old** values while `/run/secrets` holds the new ones.
The change looks deployed and is not. The tunnel then breaks the next time the
service restarts, at an uncontrolled moment.

*Rotation procedure*

1. Generate all five new values plus the Reality keypair locally.
2. Write server values to `ssdnodes-1.yaml` and the matching client values
   (`vless_uuid`, `reality_public_key`, `reality_short_id`, `hy2_password`,
   `hy2_obfs_password`) to `driver.yaml` in **one commit** — a half-rotated
   pair guarantees a broken tunnel.
3. Push, bump `flake.lock`, deploy `ssdnodes-1`, then **`systemctl restart
   sing-box`** explicitly.
4. Deploy `driver`; the client unit is on-demand (`sstunnel` owns it), so
   `sstunnel off && sstunnel on` is the restart.
5. Verify: `sstunnel on && curl -4 -s https://ifconfig.me` → `172.93.51.14`;
   `sstunnel status` shows the active outbound; both `vless` and `hy2` paths
   tested.

*Hardening follow-up*: add `restartUnits = [ "sing-box.service" ]` to these
`sops.secrets` declarations on both hosts so a future rotation cannot silently
no-op.

## Rotation log

| # | Secret | Researched | Rotated | Deployed | Verified |
|---|---|---|---|---|---|
| 1 | `cloudflare-token` (ssdnodes-1) | ✅ | n/a — migrated, not rotated | ✅ ssdnodes-1 | ✅ `/run/secrets` byte-identical; token `active` |
| 2 | sing-box proxy set (ssdnodes-1 + driver) | ✅ R1 | ✅ 9e493f62 | ✅ both hosts | ✅ egress `172.93.51.14` via rotated creds |
| 3 | `forgejo_runner_ssh_key` (crown jewel) | ✅ R2 | ✅ bd4daf6b + 6d746afb | ✅ all 10 hosts | ✅ runner→`nixdeploy` works; old fp absent on all 10 |
| — | (all others) | pending | | | |

## BLOCKER — `driver` cannot be built (pre-existing, unrelated to rotation)

Discovered 2026-10-26 while deploying the sing-box client half.

`nix/machines/_common/fingerprint-reader.nix` sets
`services.fprintd.tod.driver = pkgs.libfprint-2-tod1-goodix`, whose source is
fetched from `git.launchpad.net`. Launchpad is unreachable from every fleet
host — `git ls-remote` fails with `expected flush after ref listing` even for
unrelated repos such as `ubuntu/+source/linux` — and no substitute for the
fixed-output derivation exists on `cache.nixos.org`. Any build of `driver`
therefore dies in `unit-fprintd.service` → `system-units` → `etc` → toplevel.

Evidence this predates the rotation:

- `nix flake update` in this run changed **only** `systems-secrets`; nixpkgs was
  untouched.
- `driver`'s running system (`nixos-system-driver-26.05.20261025.1f607aa`)
  contains **zero** libfprint references, so `fingerprint-reader.nix` has never
  successfully deployed.

**Action taken:** the server half was already deployed with rotated values while
the client could not follow, which is a broken tunnel. The rotation was reverted
(`systems-secrets@edd1986a`), `ssdnodes-1` redeployed, and the pair re-verified
consistent — live `/run/secrets` on the server matches the repo for all five
values, and the driver/server shared values match. The rotation is staged and
ready to re-run.

**Options to unblock, in order of preference:**

1. Wait for Launchpad reachability and re-run the rotation unchanged.
2. Drop the unfree goodix TOD plugin and rely on stock `libfprint` — the reader
   may simply not work, but the host becomes buildable and the config stops
   depending on an unreachable host.
3. Vendor the blob: fetch `libfprint-2-tod1-goodix` at `882735c6` from a network
   that can reach Launchpad and seed it into the store / an internal cache.

Option 2 is a functional change to hardware the user explicitly configured, so
it is not being done unilaterally.

### What the blocker proved about the plan

The plan's rule "do not rotate a paired secret until the dependent side can take
it" is what caught this. The rotation was executed, verified on the server, and
still had to be rolled back — because *deployability of the other end* was not
itself a pre-flight check. Added to pre-flight: **confirm every host in the
rotation set can actually build** before rotating anything it shares.

## Completion notes

### sing-box proxy set — done (re-run after Launchpad recovered)

Executed at `systems-secrets@9e493f62`, superseding the revert. Server deployed
first (`restartUnits` restarted `sing-box` automatically), then the client.
Because the client unit is on-demand and was inactive, no client restart was
needed — the new values render on next start.

Verified: all five server values and all six client values match the repo
byte-for-byte at `/run/secrets`; `sstunnel on` produced egress `172.93.51.14`
through the rotated Reality/VLESS credentials; state restored afterward.

**`sstunnel` gotcha worth knowing:** `sstunnel off` does not mean "no exit node" —
it calls `exit_node_restore()`, which runs
`tailscale set --exit-node=download-vm-xps`. So toggling the proxy off silently
routes you through the tailnet exit node. To get true direct egress you must run
`sudo tailscale set --exit-node=` afterwards. Any automation that toggles
`sstunnel` and expects the prior network posture will be wrong.

### R2 / done — `forgejo_runner_ssh_key` (fleet deploy key)

Rotated at `systems-secrets@bd4daf6b` + `systems@6d746afb`. Old
`SHA256:e/jYsZJhejkfYauyMI93QcWqHzknN6n2OU/2oajGWCU` → new
`SHA256:1GHUNvwCTpziQ5WX8hI8kYsd+fwyTT4a3+UBS6sXyHM`.

Research findings that changed the procedure:

1. **Local `nup-fleet` does not use this key.** It resolves the SSH user from
   `~/.ssh/config` (`rramirez` + `~/.ssh/id_ed25519`); only Forgejo host-mode
   jobs use `nixdeploy` via `programs.ssh.extraConfig`. So rotation could not
   lock out the operator — which is what made a single-pass swap acceptable
   instead of a two-pass both-keys-authorized transition.
2. **The value is a YAML block scalar**, not a single line. The first version of
   `rotate-sops-key.sh` replaced only the `key:` header and would have left the
   old key body in place, silently producing a corrupt key. The script now
   detects `key: |` and replaces the header *and* its indented body.
3. **NixOS writes `nixdeploy`'s authorized keys to
   `/etc/ssh/authorized_keys.d/<user>`**, not `~/.ssh/authorized_keys`
   (`AuthorizedKeysFile %h/.ssh/authorized_keys /etc/ssh/authorized_keys.d/%u`).
   A rotation verifier that greps `~/.ssh/authorized_keys` reports "no keys" and
   looks like a failure.
4. Verification: runner's `/run/secrets` fingerprint matches the new key;
   `sudo -u nixdeploy ssh nixdeploy@fwai0` returns `nixdeploy`/uid 990; all 10
   hosts authorize exactly the new fingerprint and none authorize the old one.

Two transient build failures were hit and are worth remembering as noise, not
config bugs: `homeserver` failed in `system-units` on `fwai0` twice while the
identical derivation built fine locally, and succeeded on retry.
