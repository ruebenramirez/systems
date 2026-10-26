#!/usr/bin/env bash
# rotate-sops-key.sh — replace values for named keys in a sops file, safely.
#
#   rotate-sops-key.sh <host> key=value-file [key=value-file ...]
#
# Handles both single-line values and YAML block scalars (`key: |`), which is
# how sops stores multi-line secrets such as SSH private keys.
#
# Decrypts secrets/<host>.yaml, replaces each named top-level key's value with
# the contents of the given file, re-encrypts to the recipients ALREADY recorded
# in that file, and verifies:
#   * the new file decrypts
#   * only the intended keys changed
#   * every other line is byte-identical
#   * recipient count is unchanged
# On any failed check the original file is left untouched and we exit non-zero.
set -euo pipefail

REPO="${SECRETS_REPO:-/home/rramirez/code/systems-secrets}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.ssh/id_ed25519.age}"
SOPS=(nix shell nixpkgs#sops --command sops)

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

"${SOPS[@]}" -d "$REPO/$f" > "$WORK/before.yaml"
cp "$WORK/before.yaml" "$WORK/edit.yaml"

changed=()
for kv in "$@"; do
  key="${kv%%=*}"; valfile="${kv#*=}"
  [[ -s "$valfile" ]] || { echo "empty value file for $key" >&2; exit 2; }
  grep -q "^${key}: " "$WORK/edit.yaml" || { echo "key not present: $key" >&2; exit 2; }

  # strip a single trailing newline from the value file
  val=$(<"$valfile"); val="${val%$'\n'}"

  if grep -q "^${key}: *[|>]" "$WORK/edit.yaml"; then
    # block scalar: replace the header AND its indented body
    awk -v k="$key" -v vf="$valfile" '
      BEGIN { pat = "^" k ": "; skip = 0 }
      skip == 1 { if ($0 ~ /^[ \t]/) next; else skip = 0 }
      $0 ~ pat {
        print k ": |"
        while ((getline line < vf) > 0) print "  " line
        close(vf)
        skip = 1
        next
      }
      { print }
    ' "$WORK/edit.yaml" > "$WORK/tmp.yaml" && mv "$WORK/tmp.yaml" "$WORK/edit.yaml"
  else
    awk -v k="$key" -v v="$val" '
      BEGIN { pat = "^" k ": .*" }
      $0 ~ pat { print k ": \"" v "\""; next }
      { print }
    ' "$WORK/edit.yaml" > "$WORK/tmp.yaml" && mv "$WORK/tmp.yaml" "$WORK/edit.yaml"
  fi
  changed+=("$key")
done

cp "$WORK/edit.yaml" "$WORK/work/$f"
( cd "$WORK/work" && "${SOPS[@]}" -e "$f" ) > "$REPO/$f.new"

fail() { echo "ABORT ($1) — original left untouched" >&2; rm -f "$REPO/$f.new"; exit 1; }
"${SOPS[@]}" -d --input-type yaml --output-type yaml "$REPO/$f.new" > "$WORK/after.yaml" \
  || fail "new file does not decrypt"
[[ "$(grep -c 'recipient: ' "$REPO/$f.new")" == "$RCOUNT" ]] || fail "recipient count changed"

# strip the rotated keys (header + any block-scalar body) from both sides and
# require everything else to be byte-identical
strip_keys() {
  awk -v keys="$(IFS=:; echo "${changed[*]}")" '
    BEGIN { n = split(keys, K, ":"); for (i = 1; i <= n; i++) skipre[K[i]] = "^" K[i] ": " }
    {
      for (i = 1; i <= n; i++) {
        if ($0 ~ skipre[K[i]]) { skipbody = 1; next }
      }
      if (skipbody == 1) { if ($0 ~ /^[ \t]/) next; skipbody = 0 }
      print
    }
  ' "$1"
}
strip_keys "$WORK/before.yaml" > "$WORK/b.stripped"
strip_keys "$WORK/after.yaml"  > "$WORK/a.stripped"
diff -q "$WORK/b.stripped" "$WORK/a.stripped" >/dev/null || fail "untouched lines differ"

mv "$REPO/$f.new" "$REPO/$f"
echo "ROTATED in $f: ${changed[*]}"
echo "  recipients unchanged: $RCOUNT"
echo "  all other lines byte-identical: yes"
