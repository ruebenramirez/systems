#!/usr/bin/env bash
# Build a guest's unified Incus image with the flake and stage it where the
# OpenTofu incus_image resource reads it (tofu/locals.tf `image_dir`).
#
# Usage: build-incus-image.sh <vm>
set -euo pipefail

vm="${1:?usage: build-incus-image.sh <vm>}"
repo="${REPO:-$HOME/code/systems}"
out="/devpool/incus-migration/${vm}.tar"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}
require_cmd nix
require_cmd sudo

echo "Building ${repo}#${vm}-incus-image ..."
src="$(nix build --no-link --print-out-paths "${repo}#${vm}-incus-image")"

sudo mkdir -p "$(dirname "$out")"
sudo cp "$src" "$out"
sudo chown "${OWNER:-rramirez}" "$out"
sudo chmod 0644 "$out"
echo "staged $out"