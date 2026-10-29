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

## See also

- [`docs/private-flake-input-credentials.md`](private-flake-input-credentials.md)
  — why these jobs pin `HOME` and blank the checkout `extraheader`.
- [`README.md`](../README.md) — the two jobs and the `nixdeploy` identity.
