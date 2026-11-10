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
- **The runner's container backend is Podman.** A `runs-on: docker` job goes to
  podman over the Docker API socket it serves
  (`unix:///run/podman/podman.sock`). The `nixos` host-mode label both workflows
  here actually use never touches a container engine at all.
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
   host does not leave the rest unpatched. Hosts marked `offlineOk = true` in
   `nix/lib/inventory.nix` (laptops) are skipped with a warning when ssh fails
   instead of failing the run; naming one explicitly still demands a deploy.
4. `scripts/ci-push-flake-lock.sh` — pushes the new `flake.lock` if at least one
   machine was updated, even when the run is red. A targeted dispatch
   (`machines=` set) never pushes.
5. `scripts/ci-alert-mail.sh` — mails the failure with per-machine results. If
   the checkout is what failed there is no script to run, so the step falls back
   to a bare note through `msmtp`, which the runner's own config provides.
6. `scripts/ci-arm-runner-self-switch.sh` — promises this VM its own switch 90s
   later, for the next section.

`forgejo-ci-runner-vm` is excluded from the fleet deploy (`NUP_FLEET_EXCLUDE`,
default `forgejo-ci-runner-vm`).

### Checking out a private repo

`rueb/systems` is private: an unauthenticated `info/refs` gets a `401`, and git
answers that with `could not read Username` once prompts are disabled. So every
step that touches the repo has something to authenticate with, and the two
credentials in play are deliberately different (see
[Secrets](secrets.md#the-private-systems-secrets-input)):

- `actions/checkout` uses the **per-run task token**, which dies with the run.
- nix's git subprocesses use **`nixdeploy`'s netrc** to fetch `systems-secrets`.

Both workflows blank checkout's `http.https://code.rueb.dev/.extraheader` at the
top level so that nix falls back to that netrc. That blank outranks the header
checkout writes into the repo's own config -- a `GIT_CONFIG_*` overlay beats
`--local` -- so each checkout step has to un-blank it with
`GIT_CONFIG_COUNT: "0"`. A blanked checkout has *no* credential at all: the task
token is discarded and checkout points git at a temporary `HOME`, out of reach of
the netrc. (`git -c key=value` outranks the overlay, which is why the persist
step's override below works.)

Every step after checkout is gated on its outcome, and a guard step checks the
tree exists, because checkout deletes the workspace before it fetches: run 211
(2026-11-05) found the repo had quietly gone private overnight, both jobs died at
checkout, and every following step failed with `127: No such file or directory`
-- including the step that mails the failure. A red nightly must still reach a
human, so the guard is a plain test for the files on disk and does not depend on
an expression evaluating. The Matrix notify job has no such fallback -- its
script is in the checkout too -- so the failure mail is the alert that has to
survive a dead checkout on its own.

### The runner deploys itself

The runner is the one fleet member the deploy job cannot switch: activation
restarts `forgejo-ci-runner.service` and takes the running job with it. So the
job only arms a transient systemd unit, and 90 seconds later -- once the job has
released the machine -- `runner-self-switch.service` fetches `master` into
`/var/lib/nixdeploy/fleet` and runs `nup-fleet forgejo-ci-runner-vm` against it.

- The last applied revision is recorded, so a tick on an unchanged rev costs a
  `git fetch` and a comparison: no evaluation, no build, no ssh.
- If a job happens to be in flight when the unit fires, it re-arms five minutes
  out rather than holding the unit open.
- A failed switch leaves the revision unrecorded and re-arms once. A timer at
  09:00 and 21:00 America/Chicago -- pinned, so it cannot drift with the host's
  `time.timeZone` -- covers the runs that died before arming and a failure
  that no new commit follows.
- **It has to be installed once by hand.** The unit exists only after a switch has
  installed it, and the switch that installs it is the one this mechanism performs,
  so the first one comes from outside: `dotfiles/bin/nup-fleet forgejo-ci-runner-vm`
  from a workstation holding the git credential. Until that lands, the arm step
  fails the run instead of noting that there is nothing to arm -- a runner that
  cannot self-deploy is exactly what this section exists to prevent.
- Log: `/var/lib/nixdeploy/runner-self-switch.log`. To force it:
  `sudo systemctl start runner-self-switch.service`. Starting it a second time
  should log `already at <rev>; nothing to do` in well under a second.

### A switch that drops its own ssh connection

Activating a config can restart the network the deploy is riding on. When it
does, the ssh session carrying `switch-to-configuration switch` dies mid-call,
ssh exits 255, and nix reports it as:

```text
error: while running command with remote sudo, did you forget to use --ask-sudo-password?
```

That message is a guess, and so far it has always been wrong: sudo was fine, the
credential was fine, the machine switched. Run 226 reported
`Failed machines (1): homeserver` for a host that had just made a new generation
current and active underneath the dying connection. A red that needs no action is
worse than no red, because it trains you to ignore the nightly.

`nup-fleet` counts a failed switch as updated only when it can show both:

- the failure text looks like a lost transport -- ssh 255, connection reset or
  closed, broken pipe, that `--ask-sudo-password` line -- and
- the target answers ssh again (retried for 30 seconds, since a tailnet link
  usually takes a few) and is on a **different** system profile than the one it
  held when the switch began.

It logs a `::warning::` naming the new system and the host counts as updated.
Neither half alone is enough: a real activation error still fails, and a host
that never comes back still fails. The profile is compared against the pre-switch
value rather than the path just built, so confirming costs no evaluation.

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
