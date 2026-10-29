# CI workflow policy

Rules for `.forgejo/workflows/` in this repo. These jobs hold real privilege,
so the constraints are tighter than for a typical project.

## Pin actions to full commit SHAs

Every `uses:` step is pinned to a **full commit SHA** with a trailing comment
naming the release it resolves to:

```yaml
uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262 # v4.4.0
```

Mutable tags are not acceptable here. A tag can be retagged by whoever owns it,
and these jobs run with a workflow token that can push to this repo while
holding SSH to every machine as a `trusted-user` with `NOPASSWD` sudo — an
upstream account compromise becomes root on the fleet. Pinning the SHA makes
any upstream change a deliberate, reviewable commit.

To bump a dependency, resolve the tag to a commit and edit both the SHA and the
comment:

```bash
git ls-remote --tags https://github.com/actions/checkout | grep 'refs/tags/v4'
```

If the tag is annotated, `refs/tags/vX.Y.Z^{}` holds the commit; the SHA to pin
is the commit, not the tag object.

## Pull request checks

[`pr-check`](../.forgejo/workflows/pr-check.yaml) runs on every push to an open
PR (`opened`, `synchronize`, `reopened`) against `master`, and nothing else. It
validates; it never deploys, never activates, and never pushes.

It runs `nup-fleet --check`, which stops at the first failing phase:

1. **parse** (locally) — `nix-instantiate --parse` over every `.nix` file in the
   tree, including ones no configuration imports (templates, unpackaged
   derivations): evaluation only parses what it reaches. Under a second.
2. **ship** (locally) — `nix copy` the flake source and every locked input to
   `fwai0`. After a nightly there is nothing to send.
3. **evaluate** (on `fwai0`) — `nix flake check --no-build`, which forces every
   `nixosConfigurations` entry to its toplevel derivation and validates the shape
   of every other flake output. This is where a mistyped option, a bad type or a
   broken module surfaces. About 26s.
4. **build** (on `fwai0`) — each configuration's toplevel realised there, results
   left there. Seconds per host once the nightly has built them.

About a minute end to end for the whole fleet. A PR that moves `flake.lock` is
the case that really builds, and that is the case worth the `timeout-minutes`.

### Required status check

`master` is protected and requires this context:

    flake check (PR) / check (pull_request)

Forgejo builds it as `<workflow name> / <job id> (<event>)`, so renaming the
workflow's `name:` or the `check` job id orphans the rule: the required context
stops reporting and PRs stall instead of gating. Update the rule in the same
change that renames either:

```bash
curl --netrc -X PATCH \
  https://code.rueb.dev/api/v1/repos/rueb/systems/branch_protections/master \
  -H 'Content-Type: application/json' \
  -d '{"enable_status_check": true,
       "status_check_contexts": ["flake check (PR) / check (pull_request)"]}'
```

Note the rule has `apply_to_admins: false`, so the repository owner can still
merge a red PR; flip that flag in the same call if the gate should bind everyone.
The `flake.lock` commit the nightly pushes is unaffected either way: it is exempt
through `unprotected_file_patterns`.

### Everything heavy runs on `fwai0`

The runner is a 4-core VM with 3845 MB, and the first version of this check
evaluated the fleet on it. A single `nix flake check --no-build` forces every
configuration into one process and peaks near 3.5G; that `nix` is a child of
`forgejo-runner.service`, so the OOM killer took the runner down with the job
(`forgejo-ci-runner.service: Failed with result 'oom-kill'`) and everything else
in flight with it. Evaluating one configuration per process does fit — 1.0–1.8G
for the largest host — but costs a minute of wall clock and gives up the
flake-output checks, so that is not what runs.

The invoking host therefore only parses and copies paths; the evaluation and
every build happen on the builder, which has 32 cores and 128G. Two things make
that work:

- The builder has to resolve the lock, so the flake source *and every input* are
  copied with `nix copy`. That includes the private `systems-secrets` input, for
  which the builder holds no credential: the invoking host fetches it with its own
  netrc and ships it over. Inputs the builder already has are skipped, so the
  common case copies nothing.
- Anything sent over ssh goes as a script on stdin (`ssh host bash -s`), because
  the builder's login shell is fish and would otherwise try to expand the
  `${ ... }` of a Nix expression passed as an argument.

`nix build --store ssh://fwai0 <drv>` looks like a shortcut for all of this and is
not: it treats the `.drv` as a store path to *copy*, builds nothing, and exits 0
— a gate built on it would pass unconditionally. Passing a flake installable to a
remote `--store` fails outright (`getFSAccessor is not supported by an ssh
store`), and `--eval-store` does not help: building through a non-local primary
store needs the remote-builds machinery, which is what copies the closure back.

The invoking host still needs the inputs in its own store, to resolve
`nix flake metadata` and to copy them on; the nightly keeps them warm.

### What the check does not cover

- **sops secret existence.** `scripts/check-sops-secrets.sh` still runs in the
  nightly before the deploy. A PR can add a `sops.secrets.<name>` that no host
  has a key for and stay green until it merges.
- **Formatting.** The flake publishes a `formatter`, so
  `nix fmt -- --check $(git ls-files '*.nix')` works, but most of the tree
  predates nixfmt and is not clean, so the check does not gate on it. New code
  should follow the RFC 166 style nixfmt defines; a repo-wide `nix fmt` is a
  commit of its own.
- **forks.** The private `systems-secrets` input has to be fetchable, so a PR
  from a fork without a credential for `code.rueb.dev` fails at the preflight.

## Nightly upgrade monitoring

The [`nup-fleet-upgrade`](../.forgejo/workflows/nup-fleet-upgrade.yaml) workflow
mails `r3v2@rueb.dev` when either job fails, with the per-machine results and
the tail of the run. The transport is `msmtp` submitting to Stalwart over the
tailnet, installed and configured by
[`ci-alert-mail.nix`](../nix/machines/forgejo-ci-runner-vm/services/ci-alert-mail.nix)
— the same reasoning as
[`failure-mail.nix`](../nix/machines/_common/base/failure-mail.nix): a nightly
that dies at 03:30 and is only visible to someone who opens the Actions UI is
not monitoring. A run that is merely cancelled or skipped stays quiet.

## Pushing to the protected `master` branch

`master` is protected, and the workflow's automatic `GITHUB_TOKEN` cannot push to
it. That token is an Actions *task* token, not a personal access token: it
authenticates as the `forgejo-actions` system user (uid `-2`), which has no row
in the user table. The protected-branch hook looks the pusher up by id before any
whitelist or file-pattern exception is consulted, so every push of a protected
ref with that token fails with `Forgejo: Internal Server Error` — there is no
branch protection setting that makes it work. `actions/checkout` installs the
token as a git `extraheader`, so the credential has to be overridden explicitly
at push time; the `Persist updated flake.lock` step blanks that header and
authenticates with the `CI_FLAKELOCK_PUSH` secret instead.

The protection rule keeps `master` closed to direct pushes and lists `flake.lock`
as an unprotected file pattern, so the only commits that reach it are ones that
touch nothing else. That exception is file-scoped, not person-scoped: it applies
to any identity with write access, which is why the push still needs a credential
of its own rather than riding on the task token.

## Not re-triggering the workflow from its own lockfile commit

That push lands on `master`, which is also what starts the workflow, so every run
would schedule the next one. The `push` trigger carries
`paths-ignore: [flake.lock]`, which Forgejo matches against every path changed
between the pre-push and post-push tip: a lock-only push starts no run, a merge
that touches anything else still does. So `Persist updated flake.lock` must keep
committing `flake.lock` alone, and a merged PR that changes only the lockfile is
left to the nightly schedule.

## See also

- [`docs/private-flake-input-credentials.md`](private-flake-input-credentials.md)
  — why these jobs pin `HOME` and blank the checkout `extraheader`.
- [`README.md`](../README.md) — the two jobs and the `nixdeploy` identity.
