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

## See also

- [`docs/private-flake-input-credentials.md`](private-flake-input-credentials.md)
  — why these jobs pin `HOME` and blank the checkout `extraheader`.
- [`README.md`](../README.md) — the two jobs and the `nixdeploy` identity.
