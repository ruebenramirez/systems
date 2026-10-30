#!/usr/bin/env bash
#
# sops-map.sh -- print the secrets map: file, keys, the hosts that declare them,
# and the hosts that are actually recipients.
#
# The inventory table in docs/secrets.md is generated from this rather than
# typed, so it cannot silently disagree with the configs. The interesting column
# is consumers vs recipients: a consumer missing from recipients is a boot
# failure waiting to happen; a recipient missing from consumers is a revocation
# that never finished.
#
# Usage: scripts/sops-map.sh           # markdown table
#        scripts/sops-map.sh --no-hosts # omit the 10 single-consumer headscale rows
# Env:   SECRETS_DIR to skip the flake fetch.

set -uo pipefail
FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -z "${SECRETS_DIR:-}" ]]; then
  SECRETS_DIR="$(nix eval --raw --impure \
    --extra-experimental-features 'nix-command flakes' \
    --expr "builtins.toString (builtins.getFlake \"$FLAKE_DIR\").inputs.systems-secrets.outPath" 2>/dev/null)" || {
      echo "error: could not fetch systems-secrets; run scripts/setup-forgejo-netrc.sh or set SECRETS_DIR" >&2
      exit 2; }
fi

rows="$(nix eval --raw --impure --expr "
  let
    flake = builtins.getFlake \"$FLAKE_DIR\";
    triple = n: k: s:
      \"\${n}\t\${k}\t\${builtins.baseNameOf (toString s.sopsFile)}\";
  in builtins.concatStringsSep \"\n\"
       (builtins.concatMap (n: builtins.attrValues
          (builtins.mapAttrs (triple n)
            (flake.nixosConfigurations.\"\${n}\".config.sops.secrets or {})))
        (builtins.attrNames flake.nixosConfigurations))
")"
[[ -n "$rows" ]] || { echo "error: flake declares no sops secrets" >&2; exit 1; }

# age key -> host name, from the machine anchors in .sops.yaml.
declare -A KEYNAME KEYS HOSTS RECIPIENTS
while read -r name key; do KEYNAME["$key"]="$name"; done < <(
  sed -nE "s/^[[:space:]]*([a-z0-9-]+):[[:space:]]*&[a-z0-9-]+[[:space:]]+'(age1[a-z0-9]+)'.*/\1 \2/p" \
    "$SECRETS_DIR/.sops.yaml")

while IFS=$'\t' read -r host key file; do
  [[ -n "$file" ]] || continue
  KEYS["$file"]="${KEYS[$file]:+${KEYS[$file]}}$key"$'\n'
  case " ${HOSTS[$file]:-} " in *" $host "*) : ;; *) HOSTS["$file"]="${HOSTS[$file]:+${HOSTS[$file]} }$host" ;; esac
done <<< "$rows"

for f in "$SECRETS_DIR"/secrets/*.yaml; do
  base="$(basename "$f")"
  names=""
  for r in $(grep -oE 'recipient: age1[a-z0-9]+' "$f" 2>/dev/null | awk '{print $2}'); do
    n="${KEYNAME[$r]:-$r}"
    case " $names " in *" $n "*) : ;; *) names="$names $n" ;; esac
  done
  RECIPIENTS["$base"]="${names# }"
done

[[ "${1:-}" == "--no-hosts" ]] && skip_headscale=1 || skip_headscale=0

printf '| file | keys | consumers | recipients |\n|---|---|---|---|\n'
for file in "${!KEYS[@]}"; do
  [[ $skip_headscale == 1 && $file == headscale-client-* ]] && continue
  keys="$(sed '/^$/d' <<< "${KEYS[$file]}" | sort -u | sed 's/.*/`&`/' | paste -sd, - | sed 's/,/, /g')"
  printf '| `%s` | %s | %s | %s |\n' "$file" "$keys" \
    "$(tr ' ' '\n' <<< "${HOSTS[$file]}" | sed '/^$/d' | sort -u | paste -sd' ' -)" \
    "${RECIPIENTS[$file]:-none}"
done | sort
