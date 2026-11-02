# CI

Two Forgejo Actions workflows in `.forgejo/workflows/` keep the fleet safe and
current. Both run on the `nixos` host-mode runner on `forgejo-ci-runner-vm` and
share the `fwai0-builder` concurrency group, because every build must happen on
`fwai0` and must not overlap.

| Trigger | Workflow / job | Outcome |
|---|---|---|
| PR to `master` (or manual) | `flake check (PR)` / `check` | Validates only; never deploys or pushes |
| Nightly 03:30 CT, push to `master` (or manual) | `nup-fleet upgrade` / `upgrade` | Re-locks, deploys best-effort, persists the lock |

## Invariants

- **Actions are pinned to full commit SHAs** (with the release in a trailing
  comment). A tag can be retagged, and these jobs hold fleet SSH plus a
  `trusted-user` with NOPASSWD sudo — an upstream compromise would be root on
  every machine. Bump by resolving the tag to a commit and editing both.
- **One builder, one build at a time.** Every build runs on `fwai0`, so both
  workflows share `concurrency.group: fwai0-builder` with
  `cancel-in-progress: false`. Any new workflow that builds there must join it.

## Pull request check

`flake check (PR)` runs on `opened`, `synchronize`, and `reopened` against
`master`, and on manual dispatch. It validates only: nothing is deployed,
activated, or pushed back.

1. `scripts/check-sops-secrets.sh` — every declared `sops.secrets.<name>` names
   a file that exists in the locked `systems-secrets` revision, contains that
   key, and lists the declaring host as a recipient. Those are the three ways a
   secret looks fine here and fails at boot on a machine nobody is standing
   next to. The private input is resolved once for this check and the next.
2. `scripts/check-docs-paths.sh` — every `secrets/<file>.yaml` reference and
   relative markdown link resolves.
3. `nup-fleet --check` — parses every `.nix` file locally, ships the flake
   source and inputs to `fwai0`, then evaluates and builds every configuration
   there (`nix flake check --no-build`, then one `toplevel` realise per host).
   The runner never evaluates the whole fleet: that peaks near 3.5G and would
   OOM the runner. See `dotfiles/bin/nup-fleet`.

A failure pings Matrix via the signed Hermes webhook; a passing check is silent.
A fork without a credential for `code.rueb.dev` fails at the first check,
because the private input cannot be fetched.

### Required status check

`master` requires the context `flake check (PR) / check (pull_request)`, built
as `<workflow name> / <job id> (<event>)`. Renaming the workflow `name:` or the
`check` job id orphans the rule; update the protection in the same change:

```bash
curl --netrc -X PATCH \
  https://code.rueb.dev/api/v1/repos/rueb/systems/branch_protections/master \
  -H 'Content-Type: application/json' \
  -d '{"enable_status_check": true,
       "status_check_contexts": ["flake check (PR) / check (pull_request)"]}'
```

The rule has `apply_to_admins: false`, so the owner can still merge a red PR.

## Fleet upgrade

`nup-fleet upgrade` runs nightly, on every push to `master`, and on manual
dispatch (optionally naming machines). One job moves the lock exactly once:

1. `nup-fleet --flake-update-only` — `nix flake update`.
2. `scripts/check-sops-secrets.sh` — validates the *new* lock, so a fresh
   secrets revision cannot break the deploy.
3. `nup-fleet` — deploys at that lock. **Best-effort:** every reachable machine
   is upgraded; unreachable ones are reported and the run fails, so one dark
   host does not leave the rest unpatched.
4. `scripts/ci-push-flake-lock.sh` — pushes the new `flake.lock` if at least one
   machine was updated, even when the run is red. A targeted dispatch
   (`machines=` set) never pushes.
5. `scripts/ci-alert-mail.sh` — mails the failure with per-machine results.

`forgejo-ci-runner-vm` is excluded (`NUP_FLEET_EXCLUDE`, default
`forgejo-ci-runner-vm`) so a deploy cannot restart the runner mid-job; that VM
is updated manually.

### Pushing over a protected `master`

`master` is protected and the workflow token (`forgejo-actions`, uid `-2`) has
no user row, so the protected-branch hook rejects its push with an internal
error. The persist step therefore pushes with the `CI_FLAKELOCK_PUSH` secret and
a `git -c http.…/.extraheader=…` override, which outranks the blanked checkout
header. `flake.lock` is an unprotected file pattern, so a lock-only commit is
allowed; `paths-ignore` keeps that commit from retriggering the workflow.

## Notifications

Both workflows report to Matrix via the signed Hermes webhook; the nightly also
mails failures. See [Alerting](alerting.md#ci-notifications).

## See also

- [Secrets](secrets.md) — how a secret reaches a host, and the private
  `systems-secrets` input.
- [Fleet keys](fleet-keys.md) — the deploy key and other credentials.
- [Alerting](alerting.md) — how failures reach a human.
