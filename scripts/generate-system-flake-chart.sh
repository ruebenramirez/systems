#!/usr/bin/env bash
set -euo pipefail

FORK_COMMIT="ce788b1a46fd73d0e1017d0528f4e3b8a39dabb6"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MMD="$REPO_ROOT/docs/system-flake-commit-volume.mmd"
SVG="$REPO_ROOT/docs/system-flake-commit-volume.svg"

RENDER=0
SHOW_ALL=0
WINDOW_QUARTERS=12
REF="master"
while (( $# > 0 )); do
  case "$1" in
    --render) RENDER=1; shift ;;
    --all) SHOW_ALL=1; shift ;;
    --quarters)
      WINDOW_QUARTERS="${2:-}"
      [[ "$WINDOW_QUARTERS" =~ ^[1-9][0-9]*$ ]] || {
        echo "--quarters requires a positive integer" >&2
        exit 2
      }
      shift 2
      ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) REF="$1"; shift ;;
  esac
done

declare -A LABELS=(
  ["2023 Q2"]="xps17"
  ["2023 Q4"]="vmdev-mac / x220 / vmdev"
  ["2025 Q2"]="ssdnodes-1 / raspberry-pi"
  ["2025 Q3"]="homeserver"
  ["2026 Q1"]="fwai0 / dev-vm-xps / download-vm-xps / openclaw-vm / pi-syncoid-target (rename)"
  ["2026 Q2"]="forgejo-ci-runner-vm / newsletter-dev-vm / z13"
)

ym_to_idx() { local y="${1%-*}" m="${1#*-}"; echo $(( y * 4 + (10#$m - 1) / 3 )); }
idx_to_q() { local i="$1"; printf '%d Q%d' $(( i / 4 )) $(( i % 4 + 1 )); }

declare -A COUNT
while IFS=$'\t' read -r q n; do
  [ -n "$q" ] && COUNT["$q"]="$n"
done < <(
  git -C "$REPO_ROOT" log "$FORK_COMMIT^..$REF" \
    --pretty=format:%ad --date=format:'%Y-%m' |
    awk '{ split($1, a, "-"); q = int((a[2] - 1) / 3) + 1; c[a[1]" Q"q]++ }
         END { for (k in c) print k "\t" c[k] }'
)

fork_start=$(ym_to_idx "$(git -C "$REPO_ROOT" show -s --format=%ad --date=format:'%Y-%m' "$FORK_COMMIT")")
end=$(ym_to_idx "$(git -C "$REPO_ROOT" log -1 --format=%ad --date=format:'%Y-%m' "$REF")")

if (( SHOW_ALL )); then
  start=$fork_start
else
  start=$(( end - WINDOW_QUARTERS + 1 ))
  (( start < fork_start )) && start=$fork_start
fi

xlabels=""
line=""
max=0
first=1
for (( i = start; i <= end; i++ )); do
  q="$(idx_to_q "$i")"
  n="${COUNT[$q]:-0}"
  (( n > max )) && max=$n
  if (( first )); then first=0; else xlabels+=", "; line+=", "; fi
  xlabels+="\"$q\""
  if [ -n "${LABELS[$q]:-}" ]; then
    line+="$n \"${LABELS[$q]}\""
  else
    line+="$n"
  fi
done

ymax=$(( (max + 49) / 50 * 50 ))
(( ymax < 200 )) && ymax=200

ref_hash="$(git -C "$REPO_ROOT" rev-parse "$REF")"

{
  cat <<'FRONTMATTER'
---
config:
  xyChart:
    width: 2600
    height: 1400
    titleFontSize: 56
    titlePadding: 60
    xAxis:
      labelFontSize: 28
      titleFontSize: 32
    yAxis:
      labelFontSize: 28
      titleFontSize: 32
      titlePadding: 60
  themeVariables:
    xyChart:
      plotColorPalette: "#2563eb"
  themeCSS: |
    .labels text {
      font-size: 32px !important;
      font-weight: 700;
      paint-order: stroke;
      stroke: white;
      stroke-width: 8px;
      stroke-linejoin: round;
      writing-mode: sideways-lr;
      text-anchor: middle;
    }
    .bottom-axis .label text:nth-child(even) {
      display: none;
    }
    .bottom-axis .label text {
      translate: 0 -18px;
    }
    .bottom-axis .title text {
      translate: 0 -12px;
    }
---
FRONTMATTER
  if (( SHOW_ALL )); then
    window_desc="full history since the personal fork"
  else
    window_desc="trailing $WINDOW_QUARTERS quarters ($(idx_to_q "$start") - $(idx_to_q "$end"))"
  fi
  printf '%%%% Commits reachable from %s at %s, %s.\n' "$REF" "$ref_hash" "$window_desc"
  printf '%%%% Counts use author dates and include merge commits. Labels mark the quarter in\n'
  printf '%%%% which each nixosConfigurations output was first added after the personal fork\n'
  printf '%%%% at %s.\n' "$FORK_COMMIT"
  echo "xychart"
  echo "    title \"Repo Commit Volume and Machine Additions\""
  echo "    x-axis \"Quarter\" [$xlabels]"
  echo "    y-axis \"Commits\" 0 --> $ymax"
  echo "    line [$line]"
} > "$MMD"

echo "wrote $MMD"

if (( RENDER )); then
  nix run github:NixOS/nixpkgs/nixos-unstable#mermaid-cli -- -i "$MMD" -o "$SVG"
  node "$SCRIPT_DIR/fit-chart-labels.mjs" "$SVG"
  echo "wrote $SVG"
fi
