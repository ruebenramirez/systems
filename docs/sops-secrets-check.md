# sops secrets check

`scripts/check-sops-secrets.sh` compares the `sops.secrets.<name>` a host
declares in Nix against the keys present in that host's `systems-secrets` file.
`sops-install-secrets` only validates this at build/deploy time — it fails the
`manifest.json` derivation — which is exactly how a deploy can break on a
machine far from where the config change was made. This script surfaces the
same error up front, and gates the nightly fleet upgrade.

## Running it

```bash
scripts/check-sops-secrets.sh            # every nixosConfigurations host
scripts/check-sops-secrets.sh driver     # a subset
```

It resolves `systems-secrets` from the revision the flake locks to, so no extra
checkout is needed — but that repo is private and is fetched over git, so the
invoking user needs the Forgejo read token in `~/.netrc` (Nix's `netrc-file`
setting does not cover `git+https://` inputs). See
[Private flake input credentials](private-flake-input-credentials.md);
[`scripts/setup-forgejo-netrc.sh`](../scripts/setup-forgejo-netrc.sh) installs
it.

Locally that means the check reads the *committed* lock. The nightly workflow
runs `nup-fleet --flake-update-only` before it, so CI judges the declarations
against the revisions the deploy is about to use rather than against whatever
the last run left locked — a secret added to `systems-secrets` since then would
otherwise read as missing and block a deploy that would have succeeded.

Decrypting is attempted when an age key is available; otherwise the encrypted
file's cleartext key names are used (sops leaves key names and the `sops:`
metadata block unencrypted).

## Severities

The script gates the nightly deploy, so it distinguishes findings that *block*
a deploy from hygiene findings that do not:

**Blocking** — exit 1, the deploy does not run:

- a declared secret has no matching key in the secrets file;
- a host declares secrets but has no secrets file;
- a config cannot be evaluated (a config that won't evaluate must never read as
  "declares nothing").

**Warning** — exit 0, annotated in the Actions run:

- orphaned keys: present in a secrets file but declared by no host. These are
  dead credentials — they still decrypt, still show up in audits, and still
  widen the blast radius of a leaked secrets repo, but no service reads them,
  so they never get rotated. Rotate them; they do not block the deploy.
- secrets files with no matching `nixosConfigurations` entry and no `sopsFile`
  declaration referencing them.

A key is only orphaned if **no** host declares it *against that file*: a shared
secrets file (e.g. `cloudflare-dns-management.yaml`) is legitimately consumed by
another machine through an explicit `sopsFile`, and treating that as orphaned
would delete a live credential.

The reasoning for the split: a hygiene finding must never leave ten machines
un-patched. A dead credential is worth a warning; an unresolvable secret is
worth stopping the deploy.

## See also

- [`docs/secret-rotation-2026-10.md`](secret-rotation-2026-10.md) — the rotation
  the reverse orphan scan fed into.
- [`docs/fleet-keys.md`](fleet-keys.md) — credentials that deliberately live
  outside sops and are therefore *not* covered by this script.
