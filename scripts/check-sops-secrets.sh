#!/usr/bin/env bash
#
# check-sops-secrets.sh -- catch `sops.secrets.<name>` declarations in Nix that
# have no matching key in the systems-secrets repo. sops-install-secrets only
# checks this at build time, so a deploy breaks on a far-away host; this surfaces
# it up front.
#
# Usage: scripts/check-sops-secrets.sh [host ...]   # default: every host
# Requires: nix, sops, jq. An age key decrypts the secrets file when present;
# otherwise the cleartext key names of the encrypted file are used.
#
# Exit: 1 = a deploy would fail (blocks); 0 = hygiene warnings only.

set -euo pipefail

err() {
  echo "FAIL  $*" >&2
  echo "::error::$*"
}

warn() {
  echo "WARN  $*"
  echo "::warning::$*"
}

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v nix >/dev/null 2>&1; then
  echo "error: nix is not on PATH; this script must evaluate the flake to find" >&2
  echo "       the systems-secrets revision it locks to." >&2
  exit 3
fi

# Private input, fetched over git: needs ~/.netrc, not nix's netrc-file.
if [[ -z "${SECRETS_DIR:-}" ]]; then
  nix_fetch_err="$(mktemp)"
  if ! SECRETS_DIR="$(
    nix eval --raw --impure \
      --extra-experimental-features 'nix-command flakes' \
      --expr \
        "builtins.toString (builtins.getFlake \"$FLAKE_DIR\").inputs.systems-secrets.outPath" \
      2>"$nix_fetch_err"
  )"; then
    echo "error: could not fetch the systems-secrets flake input from $FLAKE_DIR" >&2
    echo "       that repo is private and is fetched with git credentials: the" >&2
    echo "       invoking user's ~/.netrc (so HOME must be the deploy home), not" >&2
    echo "       nix's netrc-file setting." >&2
    echo "       nix said:" >&2
    sed 's/^/         /' "$nix_fetch_err" >&2
    rm -f "$nix_fetch_err"
    exit 2
  fi
  rm -f "$nix_fetch_err"
fi
SECRETS_DIR="${SECRETS_DIR:-$FLAKE_DIR/../systems-secrets}"

if [[ ! -d "$SECRETS_DIR/secrets" ]]; then
  echo "error: secrets repo not found at $SECRETS_DIR" >&2
  echo "       set SECRETS_DIR=/path/to/systems-secrets" >&2
  exit 2
fi

# Hosts come from nixosConfigurations, not the secrets directory: a file with
# no matching config has nothing to validate.
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

# Every (secrets-file, key) pair declared in the flake: used to tell a shared
# secrets file from a retired one, and by the orphan scan below.
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
  err "could not enumerate declared sops secrets"
  exit 1
fi

# A secrets file with no host config is only suspicious if nothing references
# it: shared files (e.g. cloudflare-dns-management.yaml) are pulled in through
# an explicit `sopsFile`.
for f in "$SECRETS_DIR"/secrets/*.yaml; do
  h="$(basename "$f" .yaml)"
  if ! printf '%s\n' "${config_hosts[@]}" | grep -qxF "$h"; then
    if printf '%s\n' "$referenced" | cut -f1 | grep -qxF "$h.yaml"; then
      echo "SHARED  $h.yaml: no host config of that name, but referenced by a sopsFile declaration"
    else
      warn "$h: secrets file present but no nixosConfigurations entry and nothing references it"
    fi
  fi
done

fail=0
for host in "${hosts[@]}"; do
  secrets_file="$SECRETS_DIR/secrets/$host.yaml"
  if [[ ! -f "$secrets_file" ]]; then
    # No secrets file is fine only if nothing is declared; check rather than
    # skip so a new host declaring secrets without a file is caught.
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
      err "$host: declares sops secrets but has no secrets file ($(basename "$secrets_file"))"
      printf '        - %s\n' $declared >&2
      fail=1
    else
      echo "SKIP  $host (no secrets declared, no secrets file)"
    fi
    continue
  fi

  # Only secrets resolving to this host's defaultSopsFile; an explicit
  # `sopsFile` is validated against its own file. An eval failure is fatal --
  # a config that won't evaluate must not read as "declares nothing".
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
    err "$host: could not evaluate nixosConfigurations.$host"
    fail=1
    continue
  fi

  # Top-level keys of the secrets file. Names may contain `-`. Decrypt when an
  # age key exists; otherwise read the encrypted file, where sops leaves key
  # names in cleartext -- skipping the indented `sops:` metadata block.
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
    err "$host: declared but missing from $(basename "$secrets_file")"
    printf '        - %s\n' "${missing[@]}" >&2
    fail=1
  else
    echo "OK    $host"
  fi
done

# ---------------------------------------------------------------------------
# Reverse scan: keys in a secrets file that no host declares -- dead credentials
# that still decrypt, still show in audits, and never get rotated.
#
# Orphaned only if NO host declares the key against that file: shared files are
# legitimately consumed via an explicit `sopsFile`.
# ---------------------------------------------------------------------------
echo
echo "reverse scan (secrets present but undeclared):"

orphans_total=0
if [[ -z "$referenced" ]]; then
  err "reverse scan produced no declarations; refusing to call anything orphaned"
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
      warn "$host: present in $(basename "$f") but declared by no host (${#orphans[@]} key(s))"
      printf '          - %s\n' "${orphans[@]}"
      orphans_total=$(( orphans_total + ${#orphans[@]} ))
    fi
  done
  if [[ $orphans_total -eq 0 ]]; then
    echo "clean   no orphaned secrets"
  else
    echo "note    $orphans_total orphaned secret(s) reported as warnings; rotate them, they do not block the deploy"
  fi
fi

if [[ $fail -eq 0 ]]; then
  echo
  echo "PASS  every declared sops secret resolves"
else
  echo
  echo "BLOCKED  at least one declared sops secret is unresolvable; the fleet deploy must not run"
fi

exit "$fail"
