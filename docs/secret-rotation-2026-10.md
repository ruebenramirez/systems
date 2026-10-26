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
| 4 | backup pivot keys ×3 | ✅ R3 | ✅ 321d5b04 + 07d516ee | ✅ homeserver, ssdnodes-1, hermes-vm-xps | ✅ all 3 backup services ran `success`; old fps absent |
| 5 | 3 orphan keys deleted | ✅ | ✅ 00c5a485 | n/a | ✅ reverse scan: 0 orphans, 0 missing |
| 6 | `tailscale-auth-key` ×10 (was 1 shared key) | ✅ R4 | ✅ f185402e + 3c29df63 | ✅ all 10 | ✅ all Running; canary enrollment rc=0; old key expired |
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

### R3 / done — the three backup pivot keys

`matrix_backup_ssh_private_key`, `hosted_sites_backup_ssh_private_key`,
`hermes_backup_ssh_private_key` — all three live in `homeserver.yaml` and are
**YAML block scalars**.

How each works:

| Key | Puller (homeserver) | Public half committed in | rrsync jail |
|---|---|---|---|
| matrix | `srv/matrix-backup.nix` → `root@ssdnodes-1:` | `ssdnodes-1/srv/matrix-backup-source.nix` | `rrsync -ro /srv/matrix` |
| hosted-sites | `srv/hosted-sites-backup.nix` → `root@ssdnodes-1:` | `ssdnodes-1/srv/hosted-sites-backup-source.nix` | `rrsync -ro /srv` |
| hermes | `srv/hermes-backup.nix` → `root@hermes-vm-xps:` | `hermes-vm-xps/services/hermes-backup-source.nix` | `rrsync -ro /srv/hermes` |

Each public half sits in a `from="100.64.0.1/32",restrict,command="<wrapper>"`
prefix on **root's** `authorized_keys`. That prefix is the entire safety model on
a public VPS: drop `from=` and any host may connect, drop `restrict,command=`
and the key becomes a full root shell instead of a read-only rsync of one
directory. The rotation therefore replaced *only* the key material and comment,
never the prefix.

Notes found while researching:

- The pullers use `ssh -F /dev/null -i <sops path> -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts
  -o UserKnownHostsFile=/dev/null`, so host keys are unaffected by this rotation.
- `matrix-backup-source.nix` does **not** set `PermitRootLogin`; it relies on
  `hosted-sites-backup-source.nix`'s `mkForce "forced-commands-only"` on the same
  host. Removing the hosted-sites module would silently change root login
  behaviour for the matrix key too.
- **Pre-flight mattered**: all three backups were confirmed `result=success`
  *before* rotating. Without that baseline, a post-rotation failure would have
  been ambiguous.
- Verification after deploy: each service run with `systemctl start --wait`
  returned `success`/exit 0, and the old public fingerprints are absent from
  `/etc/ssh/authorized_keys.d/root` on both source hosts.

### Orphan cleanup

Deleted via `scripts/delete-sops-keys.sh`: `homeserver:matrix_backup_ssh_public_key`,
`ssdnodes-1:continuwuity-registration-token`, `ssdnodes-1:matrix_backup_ssh_private_key`.
Reverse scan now reports zero orphans and zero missing across all 10 hosts.

The delete guard asks Nix which keys are declared **for that host** rather than
grepping the repo — `matrix_backup_ssh_private_key` is legitimately declared for
`homeserver`, so a repo-wide grep wrongly refused to delete it from
`ssdnodes-1.yaml`.

### R4 — headscale pre-auth keys

**The finding that mattered most.** All 10 hosts carried the *same* headscale
pre-auth key (user `rueb`, `reusable=true`, expiry effectively never — 156 years).
One leak anywhere in the fleet meant unlimited permanent rogue-node enrollment
into the tailnet. That is a worse standing exposure than any single service
credential in this repo.

**How the key is actually consumed** (`tailscaled-autoconnect`): it polls
`BackendState` and runs `tailscale up --auth-key $(cat /run/secrets/tailscale-auth-key)`
**only** when the state is `NeedsLogin`, `NeedsMachineAuth` or `Stopped`. A
`Running` host never re-reads the key. Two consequences:

- rotating a key cannot break an enrolled, healthy host;
- rotating is meaningless unless the old key is **revoked in headscale** —
  rewriting the sops value changes nothing about what headscale accepts.

**Replacement:** per-host, non-reusable, 365-day expiry (headscale ids 16–25).
Blast radius of a single leak drops from "unlimited nodes as rueb" to "one node,
one host, expiring". Tradeoff accepted: a host that needs to re-enroll after its
key expires needs a freshly minted one — `sudo headscale preauthkeys create -u 1
-e 8760h -o json` on the homeserver, then rotate that host's sops value.

**Verification:** all 10 hosts `BackendState=Running` and `/run/secrets` matches
the minted value; a canary key enrolled `pi-syncoid-target` with `rc=0`, proving
the mint→enroll path works; old shared key id 1 confirmed expired.

### Incident during R4 — all ten host keys expired by mistake

To decide which headscale keys to expire, I compared deployed key values against
`headscale preauthkeys list`. **That can never work: headscale masks the key in
`list` output** (`hskey-auth-XXXX***********`, 27 chars). Nothing matched, so the
"expire everything that isn't a host key" loop expired the ten host keys along
with the canaries.

No host was displaced — node keys are independent of pre-auth keys, so every host
stayed `Running` throughout — but the fleet was left unable to re-enroll until
fixed. Remediation: minted a fresh set (ids 16–25), redeployed all ten hosts,
re-verified.

Two durable rules from this:

1. **Capture the key id at creation.** `preauthkeys create -o json` returns the
   `id`; that is the only reliable handle for later expiry. Value comparison
   against `list` is not possible.
2. A loop whose branches are "keep" vs "destroy", driven by a comparison whose
   failure mode is silent non-matching, is the worst possible shape. It should
   have had an assertion that at least one value matched before expiring anything.

Also noted: `tailscale up` echoes the auth key back in its error output, so a
failed re-auth leaks the key into whatever captured the output. Redact it.

### Proof that the old fleet key cannot enroll nodes

"Expired" is a state; the requirement is a capability. Tested directly: a second
`tailscaled` was started on `fwai0` with a fresh state file, its own socket and
`--tun=userspace-networking` (so it could not disturb the host's real tunnel),
and asked to enroll with the old shared key.

```
key: 88 chars, prefix hskey-auth-9gy...
rc=1
backend error: authkey expired
backend: "BackendState": "NeedsLogin"
```

Headscale node count was 14 before and after — no new node was created. Test
artifacts and the temporary `tailscaled` were removed afterwards.

Note the key is **expired, not deleted**: the row still exists in headscale's
store but is inert. `headscale preauthkeys delete --id <n>` would remove the
records (ids 1 and 3–15) for tidiness; it changes no security property.

**Still open:** pre-auth key id 2 (user `moni`) is `reusable=true` with an
expiry ~100 years out — the same pattern that made the fleet key dangerous, just
scoped to one user. Left untouched deliberately; it may back family devices.

### R5 — `matrix-admin-access-token`: an outage, not a rotation

**The stored token was already dead.** `matrix-snapshot.service` had failed 20
consecutive runs with `401 M_UNKNOWN_TOKEN` and zero successes; the last good
export was Oct 10 05:30. Because the script is `set -euo pipefail`, the failed
`curl` aborted it *before* either rsync, so neither the RocksDB checkpoint nor
the media copy ran. Continuwuity's own `database_backup_path` was equally frozen
at Oct 10. Meanwhile `matrix-backup` on the homeserver reported `success` every
day — rsyncing stale data is a success. **16 days of Matrix backups did not
exist, and the pipeline's health check could not tell.**

**Re-issue path (no outage needed).** Continuwuity's `admin users issue-token`
requires the user's current password, and the admin console needs exclusive DB
access (`--maintenance`) — which would have meant downtime. Ordinary
`m.login.password` against `127.0.0.1:6167` worked instead and returned a valid
token, so no password change and no outage. Syntax was proven first against a
throwaway copy of the DB (`--option database_path=...` on a different listen
port) so the production path had no unknowns.

**Verification that counted:** not the exit code, but fresh bytes — export and
`db-backups` moved from Oct 10 to Oct 26 10:21, and the homeserver pull at
`/tank/backups/ssdnodes-1/matrix` showed the same fresh `.sst` files.

**Cleanup:** the copy DB (which contained password hashes and a test password)
and the temp token were shredded; the extra device session created by the
verification login was deleted via UIA. `@r3v2`'s password was **not** changed
on production.

### Standing gaps this exposed

1. **No alarm on `matrix-snapshot` failure.** 20 silent failures.
2. **`matrix-backup` measures the wrong thing.** Success should require the
   export to be *fresh* (newest file < ~12h), not merely rsync exit 0. A backup
   that cannot distinguish stale from current is not a backup.
3. Verification checks must distinguish *empty* from *zero*. Four separate checks
   this session passed vacuously: an empty grep pattern, a key recovery that
   returned 0 chars, a missing `strings` binary, and a `jq` boolean written as
   `x and "A" or "B"`.

### Guards added after the silent-backup failure

**1. `rueb.failureMail` (`nix/machines/_common/base/failure-mail.nix`)**

Opt-in per machine and per unit: watched units get
`OnFailure=failure-mail@%n`, and the template unit mails a `systemctl status`
plus journal excerpt to `r3v2@rueb.dev`. systemd has no global `OnFailure`, so
the watch list is explicit — deliberately so, because a laptop that briefly
loses a mount should not send mail.

Transports differ by host: `ssdnodes-1` uses its postfix sendmail wrapper;
`homeserver` has no mailer, so it submits to Stalwart over loopback with msmtp
(local `rueb.dev` mail never touches the SMTP2GO outbound route).

Watched: on `ssdnodes-1` — `matrix-snapshot`, `continuwuity`,
`sops-install-secrets`, and every `acme-order-renew-*`; on `homeserver` —
`matrix-backup`, `matrix-backup-freshness`, `hosted-sites-backup`,
`hermes-backup`, `headscale`, `sops-install-secrets`, and every
`acme-order-renew-*`. ACME is included because renewal failure is otherwise
invisible until a certificate expires.

**2. `matrix-backup-freshness.service`**

Judges freshness by a **proof-of-run marker**, not by data mtime. `matrix-snapshot`
writes `/srv/matrix/.snapshot-success` only after both rsyncs complete; the
homeserver pulls it and fails if it is older than 18h (three missed 6h runs).
This distinction matters: an idle Matrix server legitimately produces unchanged
files, so mtime staleness would cry wolf, while "the copy command exited 0" —
what the old check measured — cannot tell fresh from frozen.

It is a separate unit so a freshness alarm can fail loudly without ever being in
a position to skip a real backup.

**Verified by negative tests, not just happy paths:**

| Test | Result |
|---|---|
| marker missing | freshness `rc=1` ✅ |
| marker 30 days old | freshness `rc=1`, message names the broken job ✅ |
| marker fresh | `rc=0` ✅ |
| real failure → mail | `failure-mail@…` `Result=success`, Stalwart `delivery.completed` to `r3v2@rueb.dev` ✅ |

Three bugs were caught only because of those negative tests: `systemd.services`
keys omit `.service` (so the first version watched `matrix-snapshot.service.service`
and alerted on nothing), `%n` already includes the suffix, and Stalwart rejects a
non-FQDN EHLO with `550 Invalid EHLO domain`. A happy-path-only test would have
shipped all three silently.

**Known caveat:** alert mail from `ssdnodes-1` fails SPF/DKIM/DMARC on the
Stalwart side. It is accepted as ham today, but a stricter policy would start
dropping alerts. Fix by signing outbound or marking the tailnet relay trusted.

### R6–R9 — remaining solo-rotatable secrets

**R6 `freshrss-pass`, `searx-secret-key` (homeserver).** Both had the same defect
sing-box had: the unit referenced only the secret *path*, so a rotated value
changed no derivation and systemd never restarted the process — the rotation
would have been silently cosmetic. Added `restartUnits` (`freshrss-config`,
`searx`). Verified by reading the live `SEARXNG_SECRET` out of the running
process environment and comparing to the repo value, and by confirming both
units' `ActiveEnterTimestamp` moved to the deploy time.

**R7 `bulwark-session-secret`, `bulwark-admin-password` (homeserver).** The admin
password had been a **dead credential since Sep 17**: `ADMIN_PASSWORD` only
bootstraps the stored hash when `admin.json` is absent, and `admin.json` existed.
Rotating sops alone changes nothing. `admin.json` holds only `passwordHash`, so
it was removed after deploy to force a re-bootstrap; proven by the stored hash
changing (`14753eeb…` → `aacca9fc…`) and the container logging `Admin password
hashed and saved to admin.json`.

**R8 `hermes-dashboard-basic-auth-password` / `-secret`, `hermes-api-server-key`
(hermes-vm-xps).** The dashboard username was left alone — it is an identifier,
not a secret. Verified against the rendered managed config the container mounts,
which is the file the app actually reads. The dashboard uses a JS form login
rather than HTTP Basic, so a naive `curl -u` returns `302` for right and wrong
passwords alike; that check was discarded rather than reported as a pass.

**R9 `fwai0_builder_ssh_key`.** Rotated with a two-phase overlap so no build ever
broke: trust both public halves on `fwai0` → swap the private half on
`dev-vm-xps` → verify → remove the old half. Verified by forcing a derivation
with no substitute available (a cached `nix build` proves nothing about the
builder path), which offloaded over `ssh-ng`, and by `sshd` logging acceptance of
the new fingerprint. Negative test: the old private key, recovered from git
history, is now rejected with `Permission denied (publickey)` — and its
fingerprint was checked against the retired public key first, so the rejection
proves the right thing.

### Where user-facing credentials went

New FreshRSS, Bulwark and Hermes dashboard passwords were written to
`~/.local/share/rotated-credentials-2026-10-26.txt` (mode 600) rather than
printed into the transcript.

### R10 — WordPress DB credentials and salts (ssdnodes-1)

Two independent stacks, each `wordpress:latest` + `mariadb:latest` under
`/srv/<site>--wordpress`, created by a hand-written `deploy-site.sh` (not
declarative, not in sops). Per site the DB password lives in three places that
must agree: the MariaDB user, `wp-config.php`, and the container env.

Rotated for both sites: `wpuser`, MariaDB `root` (both hosts), the 8 salts, and
`deploy-site.sh` so future recreations match.

**Two things that are not obvious and cost an outage:**

1. **The official wordpress image does not rewrite an existing `wp-config.php`.**
   Recreating the container with a new `WORDPRESS_DB_PASSWORD` leaves the old
   password in the file, so the site 500s on a DB auth failure. The file has to
   be updated explicitly.
2. **The two sites store salts differently.** `monicarosephotography.com` has
   literal `define('AUTH_KEY', '…')` values, so the file is the place to change.
   `monicaandrueben.com` still has the image template form
   `define('AUTH_KEY', getenv_docker('WORDPRESS_AUTH_KEY', '…'))`, so its salts
   come from container env and must be rotated as `WORDPRESS_*` env vars —
   editing the file there does nothing.

**Incident.** The first attempt aborted the rotation but left the site down for
several minutes. The script piped the `ALTER USER` through `grep | head` and then
tested `$?`, which is `head`'s status — so the SQL had actually succeeded while
the script believed it failed and stopped before updating `wp-config.php` and the
container env. Result: MariaDB had new credentials nothing else knew. Recovery
needed a `--skip-grant-tables` rescue container on the same volume to reset the
users to the value the running site expected. Corrected scripts check each SQL
statement's own exit status.

**Still true:** these credentials are plaintext in `deploy-site.sh` and are not
covered by sops or the flake. New values were written to
`ssdnodes-1:/root/wp-rotate-creds.txt` (mode 600). Giving them declarative
coverage is a separate piece of work.

**Each stack is two containers, and both had to be handled.** Rotating the MariaDB
users is not sufficient: the `mariadb` container's own config still carried
`MYSQL_ROOT_PASSWORD`/`MYSQL_PASSWORD` from its creation, so the retired
passwords remained readable via `docker inspect`. Both containers in both stacks
were recreated from their `deploy-site.sh` (image pulls stripped) so nothing
retains old credentials. Order matters — the WordPress container's `--link`
bakes in the `mysql` host entry, so the DB container must be recreated before the
app container.

**Self-inflicted bug found and fixed while doing this:** my `sed` used
`s|WORDPRESS_DB_PASSWORD=.*|...|`, and `.*` swallowed the trailing ` \` line
continuation on three lines per script, leaving both `deploy-site.sh` files
silently truncated mid-command — a later run would have created containers with
no port mapping and no volumes. `bash -n` reported the files as fine, because a
swallowed continuation is still valid syntax. Caught only by reading the scripts.

Final state: both sites 200 with content intact (2155 and 999 posts), old DB
passwords rejected, no container env retains retired credentials.

### Hermes Matrix bridge: enabled but unserved

Surfaced while checking whether the Matrix recovery key was functional (it was
not — the whole bridge was down).

**Root cause: profile secret scoping.** Hermes runs with profile multiplexing,
and `get_scoped_secret` is explicit that "an installed profile secret scope is
authoritative: a scoped miss returns `default` (never borrow another profile's
value from `os.environ`)". Our Nix config supplied every `MATRIX_*` value through
the **container environment**, which the profile scope deliberately ignores. So:

- `platforms.matrix.enabled: true`, a valid `@hermes` token in the container env,
  and the bridge still never started — the exact "enabled yet silently unserved"
  case upstream added a warning for.
- Worse, the allowlist was read the same way, so it was **empty**, and the adapter
  rejected every invite "from unauthorized user" — including `@r3v2`, who is
  listed in `MATRIX_ALLOWED_USERS`. That made the misconfiguration look like an
  authorization problem rather than a plumbing one.

**Fix:** `hermes-profile-env-sync.service`, a oneshot `podman-hermes` depends on,
upserts the Matrix values Nix owns into `/var/lib/hermes/.env` (the profile
scope) before the container starts. The access token is read from the
sops-rendered env file at runtime so it never enters the Nix store; unrelated keys
in that 27 KB hand-managed file are left alone. Verified idempotent (key count
unchanged across re-runs).

**Verified from the homeserver side, not from logs:** `@hermes` shows
`joined_rooms == [!G9nnRAWV…]` — the whitelisted room — and its device
`last_seen` is current, proving an active sync rather than inferring health from
the absence of errors.

**Left alone deliberately:** `MATRIX_RECOVERY_KEY` was not synced, per
instruction. It remains invisible to the adapter for the same reason, so E2EE
backup restore is still not wired up. The pre-change profile file is preserved at
`/var/lib/hermes/.env.bak-20261026114852`.

### Correction: the "duplicate certificate" hazard was not real

Earlier notes in this document claimed `homeserver` and `ssdnodes-1` both ordering
certs for `monicarosephotography.com` / `monicaandrueben.com` created a
duplicate-certificate rate-limit hazard. That was wrong, and it was wrong because
I noticed both hosts ordered "the same domain" without checking the actual name
sets.

They are not the same:

| Host | Issued SANs |
|---|---|
| `ssdnodes-1` (WordPress) | `*.monicarosephotography.com`, `monicarosephotography.com` |
| `homeserver` (Stalwart SMTP) | `*.monicarosephotography.com` |

Let's Encrypt's duplicate-certificate limit keys on the **exact set** of DNS
names, so these are distinct certificates, not duplicates. Both are genuinely
needed, by different services.

The residual and much smaller risk is a DNS-01 race: both hosts write and delete
the same `_acme-challenge` TXT record in the same zone, and both renewal timers
are `OnCalendar=daily` with `RandomizedDelaySec=24h`, so a collision is possible
if they ever fire together. In practice their renewal windows are offset by days
because the certs were issued at different times, and each host re-checks daily
but only acts inside the last 30 days. Left as-is deliberately: reworking
certificate issuance to remove a low-probability race is a bad trade against the
risk of breaking TLS on two public sites, which is the thing that actually bit
this week.

### Correction 2: why alert mail from ssdnodes-1 fails SPF/DKIM/DMARC

The earlier caveat said alert mail "fails SPF, DKIM and DMARC" without saying why,
which invites the wrong fix. The actual cause:

- `rueb.dev` SPF is `v=spf1 ip4:172.93.51.14 -all` — the VPS's **public** address
  is already authorized.
- Postfix on `ssdnodes-1` relays to Stalwart **over the tailnet**, so Stalwart
  evaluates the connecting IP as `100.64.0.4`, which is not in the record. Hence
  `smtp.spf-ehlo-fail` / `smtp.spf-from-fail` / `dkim-fail` / `dmarc-fail` on a
  legitimate local message. Delivery still succeeded (`message-ingest.ham`)
  because DMARC is `p=quarantine` with relaxed alignment and enforcement is loose.

The mail is not really unauthenticated; it is authenticated against an address
Stalwart is not looking at. Options, in increasing order of correctness:

1. Add `ip4:100.64.0.4` to the SPF record — works for this evaluation, but puts
   carrier-NAT space in a public SPF record where it is meaningless to every
   other receiver on the internet.
2. Mark `100.64.0.0/10` as a trusted relay in Stalwart so inbound mail from it
   skips authentication checks. Correct semantics; needs the right Stalwart key
   for the installed version.
3. Submit alerts over authenticated SMTP so client identity comes from auth
   rather than IP.

Deliberately **not** done: none of these fix broken behaviour — alerts are
delivered today. Changing public SPF or the mail server's trust model to silence a
warning on a working path is the same class of low-value risk that already caused
one outage this session. Left as a documented follow-up with the diagnosis
attached, so whoever picks it up starts from the cause rather than the symptom.

## Matrix recovery key: left alone, but for a different reason than first written

Decision: **do not rotate** `matrix-recovery-key` in `hermes-vm-xps.yaml`.

**An earlier version of this section was wrong** and said so confidently. It claimed
neither `@hermes` nor `@r3v2` had cross-signing keys, based on `GET
/_matrix/client/v3/keys` returning `master=0 self=0 user=0 devices=0`. On conduwuit
that endpoint does not populate cross-signing or own device keys at all — it is
structurally incapable of showing what was being looked for. The correct endpoint is
`POST /_matrix/client/v3/keys/query`, and it must be given the object form
`{"device_keys":{"@user":[...]}}`; the array form silently returns nothing.

Actual state, verified with the right endpoints:

- **`@r3v2` cross-signing is healthy.** MK self-signed, SSK and USK both signed by
  the MK, and all 7 active devices signed by the self-signing key — i.e. every
  device is "verified by its owner".
- **`@hermes` cross-signing also exists and is healthy**: master
  `Bt/5jQBhUjyqpk9…`, self-signing `/O3yksO/…`, and its device `xVXdTHgG3J` is
  signed by that self-signing key.
- Both accounts have SSSS secrets in account_data (`m.cross_signing.master` with
  `{iv, ciphertext, mac}` under a random key id), even though conduwuit 404s on
  `/keys/device_signing/`.

**Why the stored key is still dead:** tested against both accounts using mautrix's
own `decode_base58_recovery_key()` + `calculate_hash()` — the exact code path
`verify_raw_key()` uses — the stored key's MAC matches **neither** `@hermes` nor
`@r3v2`. It is a stale value that unlocks nothing. Rotating the string in sops
would still change a credential no server will accept.

**The actually actionable finding:** the *real* SSSS recovery keys for both
accounts are not stored anywhere in this repo. They were generated by clients
(Element X most likely). If `@r3v2` loses all devices there is no recovery path —
worth confirming that the recovery key Element X produced was written down
somewhere durable.

**Note on method:** the earlier failed attempt to test ownership by computing
backup-session MACs by hand proved nothing, because the construction was never
validated against a known-good key. The test above uses the library's own
functions, so it is valid by construction. Lesson repeated from elsewhere in this
document: a check that cannot distinguish success from failure is not a check.
