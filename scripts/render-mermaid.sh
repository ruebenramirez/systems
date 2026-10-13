#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <input.mmd> <output.svg>" >&2
  exit 2
}

(( $# == 2 )) || usage

INPUT="$1"
OUTPUT="$2"

[[ -f "$INPUT" ]] || { echo "no such file: $INPUT" >&2; exit 1; }
mkdir -p "$(dirname "$OUTPUT")"

nix run github:NixOS/nixpkgs/nixos-unstable#mermaid-cli -- -i "$INPUT" -o "$OUTPUT"
echo "wrote $OUTPUT"
