# Private flake input credentials

`systems-secrets` is a **private** flake input, and it is fetched over
`git+https://` — so **git** authenticates it, from the invoking user's
`~/.netrc`. Nix's own `netrc-file` setting does **not** cover `git+https://`
inputs; that setting only applies to Nix's own libcurl fetches.

## Where the credential lives

| Host | How it gets the credential |
|------|----------------------------|
| `forgejo-ci-runner-vm` | Declaratively: the `forgejo_secrets_token` sops secret, rendered to `/var/lib/nixdeploy/.netrc` by [`nup-fleet-access.nix`](../nix/machines/forgejo-ci-runner-vm/services/nup-fleet-access.nix) |
| Every other machine (workstations included) | **Nothing.** No workstation carries it, which is why `nup-fleet --upgrade` from a laptop stops at `Username for 'https://code.rueb.dev':` — git had nothing to offer and fell back to prompting. |

## Supplying a credential on a workstation

`nup-fleet` checks for a usable credential *before* running `nix flake update`,
and exports `GIT_TERMINAL_PROMPT=0` so a missing or rejected token fails with a
recipe instead of hanging. `scripts/setup-forgejo-netrc.sh` installs one:

```bash
scripts/setup-forgejo-netrc.sh                              # prompt for a token
scripts/setup-forgejo-netrc.sh --from-runner forgejo-ci-runner-vm   # copy the runner's
scripts/setup-forgejo-netrc.sh --verify                     # test what is there
```

It writes a `machine code.rueb.dev` block to `~/.netrc` (mode 0600, replacing
any entry for that host, backing the old file up) and proves it by fetching the
private repo's HEAD. By hand, the equivalent is exactly:

```text
machine code.rueb.dev
  login <forgejo-user>
  password <token>
```

Override the host with `PRIVATE_GIT_HOST` if you use a mirror or a different
Forgejo instance.

Deploying **without** `--upgrade` needs no credential at all, provided the
revision in `flake.lock` is already in the store: `nup-fleet homeserver`.

## Lockfile safety

A failed or interrupted update must not leave damage behind. On 2026-10-27 an
aborted run rewrote `flake.lock` with a *stale* `systems-secrets` rev (88 → 86)
while exiting 1, and deploying from that lock would have shipped older secret
material to the fleet.

`nix_flake_update` now:

- keeps a copy of the pre-update `flake.lock` and restores it on **any**
  failure;
- treats an input whose locked `lastModified` moves **backwards** as a failure
  in its own right — the expired-cached-ref bug caught from the lock file
  itself, rather than from Nix's warning text (which may never reach the log if
  the run dies fetching the tree it just re-locked);
- keeps the credential preflight above as the *first* thing it does, so a
  missing token fails before the lockfile is touched at all.

## See also

- [`docs/sops-secrets-check.md`](sops-secrets-check.md) — the secrets preflight
  that runs before the nightly deploy.
- [`docs/fleet-keys.md`](fleet-keys.md) — inventory of every key/credential the
  fleet trusts, including this one.
