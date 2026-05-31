#!/usr/bin/env bash
set -euo pipefail

wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
  | awk -F'"' '/node.description/ { print $2; exit }'
