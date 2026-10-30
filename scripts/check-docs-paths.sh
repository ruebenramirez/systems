#!/usr/bin/env bash
#
# check-docs-paths.sh -- every path this repo's markdown points at must exist:
#
#   - `secrets/<name>.yaml` references resolved against the locked
#     systems-secrets revision
#   - relative markdown links to files inside this repo
#
# Docs are the only place credentials and procedures are written down, so a stale
# path here is a wrong instruction waiting for whoever is debugging at 2am. This
# is what stopped docs from silently rotting when files are renamed.
#
# Usage: scripts/check-docs-paths.sh
# Env:   SECRETS_DIR to skip the flake fetch.

set -uo pipefail
FLAKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FLAKE_DIR"

if [[ -z "${SECRETS_DIR:-}" ]]; then
  SECRETS_DIR="$(nix eval --raw --impure \
    --extra-experimental-features 'nix-command flakes' \
    --expr "builtins.toString (builtins.getFlake \"$FLAKE_DIR\").inputs.systems-secrets.outPath" 2>/dev/null)" || {
      echo "error: could not fetch systems-secrets; set SECRETS_DIR or install the git credential" >&2
      exit 2; }
fi

fails=0
mapfile -t md < <(find . -name '*.md' -not -path './result/*' -not -path './.git/*' | sort)

# Fenced code blocks are examples, not references; inline spans are kept, because
# inventory rows name real files inside backticks.
fenced_out() {
  for f in "${md[@]}"; do awk '/^```/{f=!f; next} !f' "$f"; done
}

# secrets/<name>.yaml mentioned anywhere in markdown prose.
while IFS= read -r ref; do
  [[ -f "$SECRETS_DIR/$ref" ]] \
    || { echo "FAIL  $ref referenced in docs but absent from systems-secrets"; fails=$((fails+1)); }
done < <(fenced_out | grep -ohE 'secrets/[A-Za-z0-9_-]+\.yaml' | sort -u)

# Relative links from markdown, within this repo only.
for f in "${md[@]}"; do
  dir="$(dirname "$f")"
  while IFS= read -r link; do
    [[ "$link" =~ ^(\./|\.\./) || "$link" == docs/* ]] || continue
    target="${link%%#*}"; [[ -n "$target" ]] || continue
    if [[ "$target" == docs/* ]]; then path="$FLAKE_DIR/$target"; else path="$dir/$target"; fi
    [[ -e "$path" ]] \
      || { echo "FAIL  $f links to $link, which does not exist"; fails=$((fails+1)); }
  done < <(grep -oE '\]\(([^)]+)\)' "$f" | sed 's/^](//; s/)$//' | grep -v '^http' | grep -v '^#')
done

if (( fails )); then
  echo "$fails broken reference(s)"
  exit 1
fi
echo "every secrets path and relative link in markdown resolves"
