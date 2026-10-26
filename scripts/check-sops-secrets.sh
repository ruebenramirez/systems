#!/usr/bin/env bash
#
# check-sops-secrets.sh -- catch Nix-declared sops secrets that have no
# matching key in the external `systems-secrets` repo.
#
# `sops-install-secrets` only validates this at *build/deploy* time (it
# fails the `manifest.json` derivation), which is exactly how a deploy can
# break on a machine far from where the config change was made. This script
# surfaces the same error up front.
#
# For each target host it:
#   1. Evaluates the NixOS config and extracts every `sops.secrets.<name>`
#      attribute that sops-nix will try to install.
#   2. Decrypts `systems-secrets/secrets/<host>.yaml` (using SOPS_AGE_KEY_FILE
#      or the configured age key) and lists its top-level keys.
#   3. Reports any declared secret missing from the secrets file.
#
# Usage:
#   scripts/check-sops-secrets.sh [host ...]     # default: all hosts with a secrets file
#
# Requires: nix, sops, jq. The age key that can decrypt the secrets file must
# be available (SOPS_AGE_KEY_FILE, ~/.config/sops/age/keys.txt, or ssh keys).

set -euo pipefail

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Everything below shells out to `nix eval`. Check for it explicitly: the
# SECRETS_DIR probe below swallows nix's stderr, so on a host with no nix it
# silently falls through to the workstation-only sibling path and reports
# "secrets repo not found at <path>" -- a misleading error that cost three
# nightly CI runs before anyone could see the real cause.
if ! command -v nix >/dev/null 2>&1; then
  echo "error: nix is not on PATH; this script must evaluate the flake to find" >&2
  echo "       the systems-secrets revision it locks to." >&2
  exit 3
fi

# Prefer the `systems-secrets` revision the flake actually locks to. The
# repo is publicly readable, so Nix fetches it anonymously into the store --
# no cross-repo credentials and no separate checkout required.
if [[ -z "${SECRETS_DIR:-}" ]]; then
  SECRETS_DIR="$(
    nix eval --raw --impure --expr \
      "builtins.toString (builtins.getFlake \"$FLAKE_DIR\").inputs.systems-secrets.outPath" \
      2>/dev/null || true
  )"
fi
SECRETS_DIR="${SECRETS_DIR:-$FLAKE_DIR/../systems-secrets}"

if [[ ! -d "$SECRETS_DIR/secrets" ]]; then
  echo "error: secrets repo not found at $SECRETS_DIR" >&2
  echo "       set SECRETS_DIR=/path/to/systems-secrets" >&2
  exit 2
fi

# Hosts come from the flake's `nixosConfigurations`, not from the secrets
# directory: a file with no matching config (e.g. a retired host) has
# nothing to validate.
mapfile -t config_hosts < <(
  nix eval --raw --impure --expr "
    let flake = builtins.getFlake \"$FLAKE_DIR\";
    in builtins.concatStringsSep \"\n\" (builtins.attrNames flake.nixosConfigurations)
  "
)

if [[ $# -gt 0 ]]; then
  hosts=("$@")
else
  hosts=("${config_hosts[@]}")
fi

# Every (secrets-file-basename, key) pair declared anywhere in the flake. Used
# twice: to tell a shared secrets file apart from a retired one, and by the
# reverse orphan scan at the end.
if ! referenced="$(
  nix eval --raw --impure --expr "
    let
      flake = builtins.getFlake \"$FLAKE_DIR\";
      cfgNames = builtins.attrNames flake.nixosConfigurations;
      pairs = n:
        let
          cfg = flake.nixosConfigurations.\"\${n}\";
          defaultFile = toString (cfg.config.sops.defaultSopsFile or \"\");
          secrets = cfg.config.sops.secrets or {};
          one = name:
            let
              s = secrets.\"\${name}\";
              f = if s ? sopsFile then toString s.sopsFile else defaultFile;
            in builtins.concatStringsSep \"\n\"
                 (builtins.filter (x: x != \"\")
                   [ (if f == \"\" then \"\" else builtins.baseNameOf f + \"\\t\" + name) ]);
        in builtins.map one (builtins.attrNames secrets);
    in builtins.concatStringsSep \"\\n\" (builtins.concatMap pairs cfgNames)
  " 2>/dev/null || true
)"; then
  echo "FAIL  could not enumerate declared sops secrets" >&2
  exit 1
fi

# Warn about secrets files that back neither a config nor any declaration.
# A file with no matching host is only suspicious if nothing references it: a
# deliberately shared file (e.g. cloudflare-dns-management.yaml) is consumed by
# several hosts through an explicit `sopsFile`.
for f in "$SECRETS_DIR"/secrets/*.yaml; do
  h="$(basename "$f" .yaml)"
  if ! printf '%s\n' "${config_hosts[@]}" | grep -qxF "$h"; then
    if printf '%s\n' "$referenced" | cut -f1 | grep -qxF "$h.yaml"; then
      echo "SHARED  $h.yaml: no host config of that name, but referenced by a sopsFile declaration"
    else
      echo "NOTE    $h: secrets file present but no nixosConfigurations entry and nothing references it"
    fi
  fi
done

fail=0
for host in "${hosts[@]}"; do
  secrets_file="$SECRETS_DIR/secrets/$host.yaml"
  if [[ ! -f "$secrets_file" ]]; then
    # A config with no secrets file is fine only if it declares no secrets.
    # Determine that here instead of blindly skipping, so a new machine that
    # declares secrets but has no secrets file yet is caught up front.
    declared="$(
      nix eval --raw --impure --expr "
        let
          flake = builtins.getFlake \"$FLAKE_DIR\";
          cfg = flake.nixosConfigurations.\"$host\";
          secrets = cfg.config.sops.secrets or {};
        in
          builtins.concatStringsSep \"\\n\" (builtins.attrNames secrets)
      " 2>/dev/null || true
    )"
    if [[ -n "$declared" ]]; then
      echo "FAIL  $host: declares sops secrets but has no secrets file ($(basename "$secrets_file"))" >&2
      printf '        - %s\n' $declared >&2
      fail=1
    else
      echo "SKIP  $host (no secrets declared, no secrets file)"
    fi
    continue
  fi

  # Secrets declared in Nix that resolve to THIS host's default secrets file
  # (`sops.defaultSopsFile`). Secrets that set an explicit `sopsFile` (e.g.
  # a shared file, or a different host's file) are excluded -- they are
  # validated against their own file, not this one.
  # A failure here is fatal: a config that cannot evaluate must not be
  # mistaken for a config that declares no secrets.
  if ! declared="$(
    nix eval --raw --impure --expr "
      let
        flake = builtins.getFlake \"$FLAKE_DIR\";
        cfg = flake.nixosConfigurations.\"$host\";
        defaultFile = toString (cfg.config.sops.defaultSopsFile or \"\");
        secrets = cfg.config.sops.secrets or {};
        usesDefault = name:
          let s = secrets.\"\${name}\"; in
          !(s ? sopsFile) || toString s.sopsFile == defaultFile;
        names = builtins.filter usesDefault (builtins.attrNames secrets);
      in
        builtins.concatStringsSep \"\n\" names
    "
  )"; then
    echo "FAIL  $host: could not evaluate nixosConfigurations.$host" >&2
    fail=1
    continue
  fi

  # Keys present in the secrets file (top-level only). Secret names may
  # contain hyphens (e.g. `llama-cpp-api-key`), so the class includes `-`.
  #
  # Try to decrypt first (authoritative). If no age key is available (e.g.
  # CI), fall back to reading the top-level keys straight from the
  # *encrypted* file: sops keeps key names and the `sops:` metadata block in
  # cleartext, and encrypts only the values -- so the name list is still
  # exact. The encrypted-file parser must ignore the nested `sops:` metadata
  # keys (age, lastmodified, mac, ...), which sit under the top-level `sops:`
  # key and are indented.
  if present="$(
    nix shell nixpkgs#sops --command sops -d "$secrets_file" 2>/dev/null \
      | grep -E '^[A-Za-z_][A-Za-z0-9_-]*:' \
      | cut -d: -f1
  )" && [[ -n "$present" ]]; then
    :
  else
    # Top-level keys are unindented; stop at the `sops:` metadata block.
    present="$(
      awk '/^sops:/{exit} /^[A-Za-z_][A-Za-z0-9_-]*:/{sub(/:.*/,""); print}' \
        "$secrets_file"
    )"
  fi

  missing=()
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if ! grep -qxF "$name" <<<"$present"; then
      missing+=("$name")
    fi
  done <<<"$declared"

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "FAIL  $host: declared but missing from $(basename "$secrets_file"):"
    printf '        - %s\n' "${missing[@]}"
    fail=1
  else
    echo "OK    $host"
  fi
done

# ---------------------------------------------------------------------------
# Reverse scan: keys sitting in a secrets file that nothing declares.
#
# These are dead credentials. They still decrypt, still show up in audits, and
# still widen the blast radius of a leaked secrets repo, but no service reads
# them -- so they never get rotated and nobody notices when the upstream secret
# is revoked. Three were found this way during the October 2026 rotation.
#
# A key is only orphaned if NO host declares it *against that file*: a shared
# secrets file is legitimately consumed by another machine through an explicit
# `sopsFile`, and treating that as orphaned would delete a live credential.
# ---------------------------------------------------------------------------
echo
echo "reverse scan (secrets present but undeclared):"

if [[ -z "$referenced" ]]; then
  echo "FAIL  reverse scan produced no declarations; refusing to call anything orphaned" >&2
  fail=1
else
  for f in "$SECRETS_DIR"/secrets/*.yaml; do
    host="$(basename "$f" .yaml)"
    [[ -f "$f" ]] || continue
    if present="$(
      nix shell nixpkgs#sops --command sops -d "$f" 2>/dev/null \
        | grep -E '^[A-Za-z_][A-Za-z0-9_-]*:' | cut -d: -f1
    )" && [[ -n "$present" ]]; then
      :
    else
      present="$(awk '/^sops:/{exit} /^[A-Za-z_][A-Za-z0-9_-]*:/{sub(/:.*/,""); print}' "$f")"
    fi
    [[ -z "$present" ]] && continue
    used="$(printf '%s\n' "$referenced" | awk -F'\t' -v f="$host.yaml" '$1==f{print $2}')"
    orphans=()
    while IFS= read -r k; do
      [[ -z "$k" ]] && continue
      grep -qxF "$k" <<<"$used" || orphans+=("$k")
    done <<<"$present"
    if [[ ${#orphans[@]} -gt 0 ]]; then
      echo "ORPHAN  $host: present in $(basename "$f") but declared by no host:"
      printf '          - %s\n' "${orphans[@]}"
      fail=1
    fi
  done
  [[ $fail -eq 0 ]] && echo "clean   no orphaned secrets"
fi

exit "$fail"
