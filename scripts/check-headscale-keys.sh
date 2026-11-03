#!/usr/bin/env bash
#
# check-headscale-keys.sh -- audit headscale pre-auth keys against the fleet.
#
# Exists for rueb/systems#34: a reusable, effectively non-expiring key nobody
# claimed, and a host whose stored key belongs to a different headscale user
# than its node. Both are invisible until someone cross-references
# `preauthkeys list` against sops by hand. This makes the cross-reference
# repeatable.
#
# Checks:
#   1. policy    -- every key is non-reusable and expires within
#                   MAX_EXPIRY_DAYS (default 820, ~2 mint cycles), unless
#                   excepted below.
#   2. coverage  -- each host's stored key exists in headscale; keys that
#                   match no host are reported as orphans.
#   3. alignment -- the user owning a host's key matches the user owning its
#                   node; a mismatch means re-enrollment lands the node under
#                   a different user, with different ACLs.
#
# headscale masks key values in `list` to `hskey-auth-<12-char prefix>-***`;
# the stored sops value shares that prefix, which is what makes matching
# possible without the secrets ever leaving sops. Decryption happens locally
# with the operator's age key; nothing here prints a key value.
#
# Usage:
#   scripts/check-headscale-keys.sh                       # ssh for live state
#   scripts/check-headscale-keys.sh keys.json nodes.json  # audit captured files
# Env:
#   SECRETS_DIR         systems-secrets checkout (default: flake input)
#   HEADSCALE_SSH_HOST  host to read headscale from (default: homeserver)
#   MAX_EXPIRY_DAYS     expiry threshold for check 1
# Exit: 1 = findings, 0 = clean.

set -uo pipefail
FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MAX_EXPIRY_DAYS="${MAX_EXPIRY_DAYS:-820}"
SSH_HOST="${HEADSCALE_SSH_HOST:-homeserver}"

# key id -> reason. Add here only with a recorded reason in docs/fleet-keys.md.
declare -A EXCEPTIONS=()

fails=0
err() { echo "FAIL  $*"; fails=$((fails+1)); }
ok()  { echo "ok    $*"; }

for dep in jq sops date; do
  command -v "$dep" >/dev/null 2>&1 || { echo "error: $dep is not on PATH" >&2; exit 3; }
done

if [[ -z "${SECRETS_DIR:-}" ]]; then
  command -v nix >/dev/null 2>&1 || { echo "error: nix not on PATH; set SECRETS_DIR" >&2; exit 3; }
  SECRETS_DIR="$(nix eval --raw --impure \
    --extra-experimental-features 'nix-command flakes' \
    --expr "builtins.toString (builtins.getFlake \"$FLAKE_DIR\").inputs.systems-secrets.outPath" 2>/dev/null)" \
    || { echo "error: could not fetch systems-secrets; set SECRETS_DIR" >&2; exit 2; }
fi
[[ -d "$SECRETS_DIR/secrets" ]] || { echo "error: no secrets dir at $SECRETS_DIR" >&2; exit 2; }

# ---------------------------------------------------------------------------
# Live state: pre-auth keys and nodes, as JSON.
# ---------------------------------------------------------------------------
if [[ $# -ge 2 ]]; then
  keys_json="$(cat "$1")"; nodes_json="$(cat "$2")"
else
  command -v ssh >/dev/null 2>&1 || { echo "error: ssh not on PATH; pass captured JSON files" >&2; exit 3; }
  keys_json="$(ssh "$SSH_HOST" sudo headscale preauthkeys list -o json)" \
    || { echo "error: could not read preauthkeys from $SSH_HOST" >&2; exit 2; }
  nodes_json="$(ssh "$SSH_HOST" sudo headscale nodes list -o json)" \
    || { echo "error: could not read nodes from $SSH_HOST" >&2; exit 2; }
fi

# protojson is camelCase; older output is snake_case. Normalize defensively.
keys_tsv="$(jq -r '
  def uname: (.user | if type == "object" then (.name // "") else (. // "") end);
  (if type == "array" then . else (.preAuthKeys // .preauthKeys // .preauthkeys // .) end)[]
  | [ (.id | tostring), (.key // ""), ((.reusable // false) | tostring),
      ((.expiration // .expiration_time // "") | tostring), uname ]
  | @tsv' <<< "$keys_json" 2>/dev/null)" \
  || { echo "error: could not parse preauthkeys JSON" >&2; exit 2; }
nodes_tsv="$(jq -r '
  def uname: (.user | if type == "object" then (.name // "") else (. // "") end);
  (if type == "array" then . else (.nodes // .) end)[]
  | [ (.name // ""), uname ]
  | @tsv' <<< "$nodes_json" 2>/dev/null)" \
  || { echo "error: could not parse nodes JSON" >&2; exit 2; }
[[ -n "$keys_tsv" ]] || { echo "error: no pre-auth keys parsed" >&2; exit 2; }

# hskey-auth-<prefix>-*** -> prefix; legacy plaintext keys pass through whole.
prefix_of() {
  local k="$1"
  if [[ "$k" == hskey-auth-* && "$k" == *-*** ]]; then
    local p="${k#hskey-auth-}"; p="${p%-***}"
    printf '%s' "${p:0:12}"
  else
    printf '%s' "$k"
  fi
}

now="$(date +%s)"
threshold=$(( now + MAX_EXPIRY_DAYS * 86400 ))

# ---------------------------------------------------------------------------
# 1. Policy: reusable or effectively-permanent keys need a recorded exception.
# ---------------------------------------------------------------------------
while IFS=$'\t' read -r id key reusable exp user; do
  [[ -n "${EXCEPTIONS[$id]:-}" ]] && continue
  bad=""
  [[ "$reusable" == "true" ]] && bad="reusable"
  if [[ -z "$exp" || "$exp" == 0001-* ]]; then
    bad="${bad:+$bad, }never expires"
  else
    exp_s="$(date -d "$exp" +%s 2>/dev/null || echo 0)"
    (( exp_s > threshold )) && bad="${bad:+$bad, }expires $exp (beyond ${MAX_EXPIRY_DAYS}d)"
  fi
  if [[ -n "$bad" ]]; then
    err "key id $id (user ${user:-?}, $bad) -- confirm intent, then expire it or record it in EXCEPTIONS + docs/fleet-keys.md"
  fi
done <<< "$keys_tsv"

# ---------------------------------------------------------------------------
# 2. Coverage: every host's stored key resolves to exactly one headscale key,
#    and every key resolves back to a host. Values are never printed.
# ---------------------------------------------------------------------------
declare -A KEY_USER MATCHED_HOST
while IFS=$'\t' read -r id key _ _ user; do
  p="$(prefix_of "$key")"
  if [[ -n "${KEY_USER[$p]:-}" ]]; then
    err "two headscale keys share prefix '$p' (ids ${KEY_USER[$p]} and $id); prefix matching is ambiguous"
  fi
  KEY_USER["$p"]="$id"
done <<< "$keys_tsv"

matched_ids=""
for f in "$SECRETS_DIR"/secrets/headscale-client-*.yaml; do
  [[ -e "$f" ]] || { echo "error: no headscale-client-*.yaml files in $SECRETS_DIR" >&2; exit 2; }
  host="$(basename "$f" .yaml)"; host="${host#headscale-client-}"
  val="$(sops -d --extract '["tailscale-auth-key"]' "$f" 2>/dev/null)" \
    || { err "$host: could not decrypt tailscale-auth-key (age key missing?)"; continue; }
  [[ -n "$val" ]] || { err "$host: tailscale-auth-key is empty"; continue; }
  p="${val#hskey-auth-}"; p="${p:0:12}"
  [[ "$val" == hskey-auth-* ]] || p="$val"   # legacy plaintext key
  if [[ -z "${KEY_USER[$p]:-}" ]]; then
    err "$host: stored key not found in headscale (expired, deleted, or wrong value)"
  else
    MATCHED_HOST["${KEY_USER[$p]}"]="$host"
    matched_ids+=" ${KEY_USER[$p]}"
  fi
done

while IFS=$'\t' read -r id _ _ _ user; do
  [[ " $matched_ids " == *" $id "* ]] && continue
  [[ -n "${EXCEPTIONS[$id]:-}" ]] && continue
  err "orphan key id $id (user ${user:-?}) matches no host's stored key -- expire it or record it in EXCEPTIONS + docs/fleet-keys.md"
done <<< "$keys_tsv"

# ---------------------------------------------------------------------------
# 3. Alignment: key user must equal node user, or re-enrollment moves the node.
# ---------------------------------------------------------------------------
while IFS=$'\t' read -r id _ _ _ kuser; do
  host="${MATCHED_HOST[$id]:-}"
  [[ -n "$host" ]] || continue
  nuser="$(awk -F'\t' -v h="$host" '$1==h {print $2; exit}' <<< "$nodes_tsv")"
  if [[ -z "$nuser" ]]; then
    echo "warn  $host: no node named '$host' in headscale; cannot check key/node user alignment"
  elif [[ "$kuser" != "$nuser" ]]; then
    err "$host: stored key belongs to user '$kuser' but its node is owned by '$nuser' -- re-enrollment would land the node under '$kuser' with different ACLs"
  fi
done <<< "$keys_tsv"

echo
if (( fails )); then
  echo "$fails finding(s); see docs/fleet-keys.md for remediation"
  exit 1
fi
echo "headscale key set matches the fleet (reusable/expiry policy, coverage, user alignment)"
