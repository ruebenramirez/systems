#!/usr/bin/env bash
# delete-sops-keys.sh — remove named top-level keys from a sops file.
#
#   delete-sops-keys.sh [--force] <host> key [key ...]
#
# Refuses to delete a key still declared for THAT HOST in the systems flake
# (asked via `nix eval`, not a repo-wide grep — a key declared for homeserver
# is fair game to delete from ssdnodes-1.yaml). --force overrides.
#
# Re-encrypts to the recipients already recorded in the file, then verifies:
# decrypts, recipient count unchanged, key set is exactly as intended, and all
# surviving content is byte-identical (block-scalar bodies included).
set -euo pipefail

REPO="${SECRETS_REPO:-/home/rramirez/code/systems-secrets}"
SYSTEMS="${SYSTEMS_REPO:-/home/rramirez/code/systems}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.ssh/id_ed25519.age}"
SOPS=(nix shell nixpkgs#sops --command sops)

force=0
[[ "${1:-}" == "--force" ]] && { force=1; shift; }
host="$1"; shift
f="secrets/$host.yaml"
[[ -f "$REPO/$f" ]] || { echo "no such secrets file: $f" >&2; exit 2; }

WORK=$(mktemp -d)
cleanup() { find "$WORK" -type f -exec shred -u {} + 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/work/secrets"
RECIPIENTS=$(grep 'recipient: ' "$REPO/$f" | awk '{print $2}' | paste -sd, -)
RCOUNT=$(grep -c 'recipient: ' "$REPO/$f")
printf 'creation_rules:\n  - path_regex: .*\n    age: >-\n      %s\n    unencrypted_suffix: _unencrypted\n' \
  "$RECIPIENTS" > "$WORK/work/.sops.yaml"

# remove one top-level key plus any block-scalar body it owns
strip_key() { # <infile> <outfile> <key>
  awk -v k="$3" '
    BEGIN { pat = "^" k ": "; skip = 0 }
    skip == 1 { if ($0 ~ /^[ \t]/) next; else skip = 0 }
    $0 ~ pat { skip = 1; next }
    { print }
  ' "$1" > "$2"
}

"${SOPS[@]}" -d "$REPO/$f" > "$WORK/before.yaml"
cp "$WORK/before.yaml" "$WORK/edit.yaml"

declared=$(nix eval --raw --impure --expr "
  let flake = builtins.getFlake \"$SYSTEMS\";
      cfg = flake.nixosConfigurations.\"$host\";
  in builtins.concatStringsSep \"\n\" (builtins.attrNames (cfg.config.sops.secrets or {}))
" 2>/dev/null || true)

for key in "$@"; do
  grep -q "^${key}: " "$WORK/edit.yaml" || { echo "key not present: $key" >&2; exit 2; }
  if [[ "$force" != 1 ]]; then
    if [[ -n "$declared" ]]; then
      printf '%s\n' "$declared" | grep -qxF "$key" && {
        echo "REFUSING: '$key' is declared for $host in the systems flake (use --force)" >&2; exit 3; }
    elif grep -rqE "sops\.secrets\.${key}([^A-Za-z0-9_]|$)" "$SYSTEMS/nix" 2>/dev/null; then
      echo "REFUSING: nix eval unavailable and '$key' appears in the flake (use --force)" >&2; exit 3
    fi
  fi
  strip_key "$WORK/edit.yaml" "$WORK/tmp.yaml" "$key" && mv "$WORK/tmp.yaml" "$WORK/edit.yaml"
done

cp "$WORK/edit.yaml" "$WORK/work/$f"
( cd "$WORK/work" && "${SOPS[@]}" -e "$f" ) > "$REPO/$f.new"

fail() { echo "ABORT ($1) — original left untouched" >&2; rm -f "$REPO/$f.new"; exit 1; }
"${SOPS[@]}" -d --input-type yaml --output-type yaml "$REPO/$f.new" > "$WORK/after.yaml" \
  || fail "new file does not decrypt"
[[ "$(grep -c 'recipient: ' "$REPO/$f.new")" == "$RCOUNT" ]] || fail "recipient count changed"

# expected content = before, with each deleted key (and its body) stripped
cp "$WORK/before.yaml" "$WORK/expected.yaml"
for key in "$@"; do strip_key "$WORK/expected.yaml" "$WORK/tmp.yaml" "$key" && mv "$WORK/tmp.yaml" "$WORK/expected.yaml"; done
diff "$WORK/expected.yaml" "$WORK/after.yaml" >/dev/null || fail "content differs beyond the deleted keys"

topkeys() { grep -E '^[A-Za-z_][A-Za-z0-9_.-]*:' "$1" | sed -E 's/:.*//'; }
diff <(topkeys "$WORK/before.yaml" | grep -vxF -f <(printf '%s\n' "$@")) \
     <(topkeys "$WORK/after.yaml") >/dev/null || fail "key set differs unexpectedly"

mv "$REPO/$f.new" "$REPO/$f"
echo "DELETED from $f: $*"
echo "  recipients unchanged: $RCOUNT"
echo "  all surviving content byte-identical: yes"
