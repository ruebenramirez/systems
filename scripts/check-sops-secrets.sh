#!/usr/bin/env bash
#
# check-sops-secrets.sh -- verify that every `sops.secrets.<name>` declaration in
# the flake can actually be satisfied at deploy time:
#
#   1. the file it names exists in systems-secrets
#   2. that file contains the key
#   3. this host is a recipient of that file
#
# 3 is the one that only shows up as a boot failure on a far-away machine: sops
# decrypts per file, so a file that lacks the host's key is unreadable no matter
# what the config says. Access is the recipient list, so the list is what gets
# checked.
#
# Nothing is decrypted. sops leaves key names and recipient lists in cleartext
# (only values are encrypted), so this runs unprivileged in CI.
#
# Usage: scripts/check-sops-secrets.sh [host ...]   # default: every host
# Env:   SECRETS_DIR=/path/to/systems-secrets to skip the flake fetch
# Exit:  1 = a deploy would fail; 0 = warnings only.

set -uo pipefail

FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

err()  { echo "FAIL  $*"; echo "::error::$*"; fails=$((fails+1)); }
warn() { echo "WARN  $*"; echo "::warning::$*"; warns=$((warns+1)); }
fails=0; warns=0

command -v nix >/dev/null 2>&1 || { echo "error: nix is not on PATH" >&2; exit 3; }

if [[ -z "${SECRETS_DIR:-}" ]]; then
  SECRETS_DIR="$(nix eval --raw --impure \
    --extra-experimental-features 'nix-command flakes' \
    --expr "builtins.toString (builtins.getFlake \"$FLAKE_DIR\").inputs.systems-secrets.outPath" 2>/dev/null)" \
    || SECRETS_DIR=""
  # Private input over git: needs ~/.netrc, not nix's netrc-file.
  if [[ -z "$SECRETS_DIR" ]]; then
    echo "error: could not fetch the systems-secrets flake input." >&2
    echo "       The repo is private and fetched with git credentials (~/.netrc)." >&2
    echo "       Or set SECRETS_DIR=/path/to/systems-secrets." >&2
    exit 2
  fi
fi
[[ -d "$SECRETS_DIR/secrets" ]] || { echo "error: no secrets dir at $SECRETS_DIR" >&2; exit 2; }
[[ -f "$SECRETS_DIR/.sops.yaml" ]] || { echo "error: no .sops.yaml in $SECRETS_DIR" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Declarations: host \t secret \t file, straight out of the evaluated configs.
# An eval failure is fatal: a config that will not evaluate must not read as
# "declares nothing".
# ---------------------------------------------------------------------------
if ! nix eval --raw --impure --expr "
  let
    flake = builtins.getFlake \"$FLAKE_DIR\";
    names = builtins.attrNames flake.nixosConfigurations;
    rows = n:
      let
        secrets = flake.nixosConfigurations.\"\${n}\".config.sops.secrets or {};
        row = name: s:
          if s.sopsFile == null then \"\${n}\t\${name}\t\"
          else \"\${n}\t\${name}\t\${builtins.baseNameOf (toString s.sopsFile)}\";
      in builtins.attrValues (builtins.mapAttrs row secrets);
  in builtins.concatStringsSep \"\n\" (builtins.concatMap rows names)
" > /tmp/sops-declared.$$ 2>/tmp/sops-eval.err; then
  echo "error: could not evaluate the flake; cannot check anything" >&2
  sed 's/^/       /' /tmp/sops-eval.err >&2
  exit 1
fi
declared="$(sort /tmp/sops-declared.$$)"; rm -f /tmp/sops-declared.$$
[[ -n "$declared" ]] || { echo "error: flake declares no sops secrets at all" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Recipients per file, from each file's own sops metadata (cleartext), mapped
# back to host names through the machine anchors in .sops.yaml.
# ---------------------------------------------------------------------------
declare -A KEYNAME
while read -r name key; do KEYNAME["$key"]="$name"; done < <(
  sed -nE "s/^[[:space:]]*([a-z0-9-]+):[[:space:]]*&[a-z0-9-]+[[:space:]]+'(age1[a-z0-9]+)'.*/\1 \2/p" \
    "$SECRETS_DIR/.sops.yaml"
)
[[ ${#KEYNAME[@]} -gt 0 ]] || { echo "error: no machine anchors found in $SECRETS_DIR/.sops.yaml" >&2; exit 1; }

recipients_of() { grep -oE 'recipient: age1[a-z0-9]+' "$1" 2>/dev/null | awk '{print $2}'; }

# Keys inside an encrypted file stay in cleartext; values do not. sops' own
# metadata block is indented, top-level keys are not.
keys_of() { sed -nE '/^sops:/,$d; /^["A-Za-z0-9_-]+:/p' "$1" 2>/dev/null | cut -d: -f1 | tr -d '"'; }

if [[ $# -gt 0 ]]; then
  hosts=("$@")
else
  mapfile -t hosts < <(printf '%s\n' "$declared" | cut -f1 | sort -u)
fi

# ---------------------------------------------------------------------------
# Per host: file exists, key present, host is a recipient.
# ---------------------------------------------------------------------------
for host in "${hosts[@]}"; do
  rows="$(printf '%s\n' "$declared" | awk -F'\t' -v h="$host" '$1==h')"
  while read -r s; do
    err "$host: '$s' declares no sopsFile (use secretFile \"<service-file>\")"
  done < <(printf '%s\n' "$rows" | awk -F'\t' '$3==""{print $2}')
  [[ -n "$rows" ]] || { warn "$host: declares no sops secrets"; continue; }

  while IFS=$'\t' read -r _ name file; do
    [[ -n "$file" ]] || continue
    path="$SECRETS_DIR/secrets/$file"
    if [[ ! -f "$path" ]]; then
      err "$host: $name -> $file, which does not exist in systems-secrets"
      continue
    fi
    keys_of "$path" | grep -qxF "$name" \
      || err "$host: $file has no key '$name' (declared by $host)"
    found=0
    for r in $(recipients_of "$path"); do
      [[ "${KEYNAME[$r]:-$r}" == "$host" ]] && found=1
    done
    [[ $found == 1 ]] || err "$host: not a recipient of $file (needed for '$name')"
  done <<< "$rows"
  echo "ok    $host: $(printf '%s\n' "$rows" | wc -l) secret(s) checked"
done

# ---------------------------------------------------------------------------
# Repo hygiene, in both directions.
# ---------------------------------------------------------------------------
for f in "$SECRETS_DIR"/secrets/*.yaml; do
  base="$(basename "$f")"
  printf '%s\n' "$declared" | cut -f3 | grep -qxF "$base" && consumed=1 || consumed=0
  [[ $consumed == 1 ]] || warn "$base: no config declares anything from it"
  for k in $(keys_of "$f"); do
    printf '%s\n' "$declared" | awk -F'\t' -v f="$base" -v k="$k" '$3==f && $2==k{found=1} END{exit !found}' \
      || warn "$base: key '$k' is not declared by any host"
  done
  case "$base" in
    *-server-*.yaml|*-client-*.yaml|*-client.yaml|*-shared.yaml) : ;;
    *) warn "$base: filename matches none of the four layout patterns" ;;
  esac
done

echo
if [[ $fails -gt 0 ]]; then
  echo "$fails problem(s) would break a deploy; $warns warning(s)"
  exit 1
fi
echo "all declared secrets resolve to a key in a file the host can decrypt ($warns warning(s))"
