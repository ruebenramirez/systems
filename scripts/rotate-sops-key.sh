#!/usr/bin/env bash
# rotate-sops-key.sh — replace values for named keys in a sops file, safely.
#
#   rotate-sops-key.sh <host> key=value-file [key=value-file ...]
#
# Decrypts secrets/<host>.yaml, replaces each named top-level key's value with
# the contents of the given file, re-encrypts to the recipients ALREADY recorded
# in that file, and verifies:
#   * the new file decrypts
#   * only the intended keys changed
#   * every other line is byte-identical
#   * recipient count is unchanged
# On any failed check the original file is restored and we exit non-zero.
set -euo pipefail

REPO="${SECRETS_REPO:-/home/rramirez/code/systems-secrets}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.ssh/id_ed25519.age}"
SOPS=(nix shell nixpkgs#sops --command sops)

host="$1"; shift
f="secrets/$host.yaml"
[[ -f "$REPO/$f" ]] || { echo "no such secrets file: $f" >&2; exit 2; }

WORK=$(mktemp -d)
cleanup() { shred -u "$WORK"/* 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

# catch-all creation rule so `sops -e` accepts the temp path
mkdir -p "$WORK/work/secrets"
RECIPIENTS=$(grep 'recipient: ' "$REPO/$f" | awk '{print $2}' | paste -sd, -)
RCOUNT=$(grep -c 'recipient: ' "$REPO/$f")
printf 'creation_rules:\n  - path_regex: .*\n    age: >-\n      %s\n    unencrypted_suffix: _unencrypted\n' \
  "$RECIPIENTS" > "$WORK/work/.sops.yaml"

"${SOPS[@]}" -d "$REPO/$f" > "$WORK/before.yaml"
cp "$WORK/before.yaml" "$WORK/edit.yaml"

changed=()
for kv in "$@"; do
  key="${kv%%=*}"; valfile="${kv#*=}"
  [[ -s "$valfile" ]] || { echo "empty value file for $key" >&2; exit 2; }
  grep -q "^${key}: " "$WORK/edit.yaml" || { echo "key not present: $key" >&2; exit 2; }
  val=$(<"$valfile")
  val="${val%$'\n'}"
  # replace only this key's line; values here are hex/uuid/base64url (no | or /)
  awk -v k="$key" -v v="$val" '
    BEGIN { pat = "^" k ": .*" }
    $0 ~ pat { print k ": \"" v "\""; next }
    { print }
  ' "$WORK/edit.yaml" > "$WORK/tmp.yaml" && mv "$WORK/tmp.yaml" "$WORK/edit.yaml"
  changed+=("$key")
done

cp "$WORK/edit.yaml" "$WORK/work/$f"
( cd "$WORK/work" && "${SOPS[@]}" -e "$f" ) > "$REPO/$f.new"

# --- verification gate ---
fail() { echo "ABORT ($1) — original left untouched" >&2; rm -f "$REPO/$f.new"; exit 1; }
"${SOPS[@]}" -d --input-type yaml --output-type yaml "$REPO/$f.new" > "$WORK/after.yaml" \
  || fail "new file does not decrypt"

[[ "$(grep -c 'recipient: ' "$REPO/$f.new")" == "$RCOUNT" ]] || fail "recipient count changed"

# every line NOT belonging to a changed key must be byte-identical
grep -vE "^($(IFS='|'; echo "${changed[*]}")): " "$WORK/before.yaml" > "$WORK/b.stripped"
grep -vE "^($(IFS='|'; echo "${changed[*]}")): " "$WORK/after.yaml"  > "$WORK/a.stripped"
diff -q "$WORK/b.stripped" "$WORK/a.stripped" >/dev/null || fail "untouched lines differ"

# structural diff must show only the intended keys
if ! diff <(sed -E "s/^([A-Za-z_][A-Za-z0-9_.-]*):.*/\1: <r>/" "$WORK/before.yaml") \
          <(sed -E "s/^([A-Za-z_][A-Za-z0-9_.-]*):.*/\1: <r>/" "$WORK/after.yaml"); then
  fail "structural diff unexpected"
fi

mv "$REPO/$f.new" "$REPO/$f"
echo "ROTATED in $f: ${changed[*]}"
echo "  recipients unchanged: $RCOUNT"
echo "  all other lines byte-identical: yes"
