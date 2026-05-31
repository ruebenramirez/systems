#!/usr/bin/env bash
set -euo pipefail

line="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)" || {
  echo "NOAUDIO"
  exit 0
}

if [[ "$line" == *"[MUTED]"* ]]; then
  echo "MUTED"
else
  awk '{ printf "%.0f%%\n", $2 * 100 }' <<< "$line"
fi
