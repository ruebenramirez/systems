#!/usr/bin/env bash
# Stage powered-off libvirt qcow2 disks as unified Incus VM image tarballs.
#
# The lxc/incus provider (v1.2.0) reads `source_file.data_path` as a FILE, so a
# unified image must be a tarball containing metadata.yaml + rootfs.img (it does
# not accept a directory).
#
# The source qcow2 is COMPACTED with `qemu-img convert -c` so that bloated/dead
# clusters (freed inside the guest but never discarded to the host) are dropped.
# Run on xps17 before `tofu apply`.
#
# Usage: stage-libvirt-disks.sh [vm ...]      (default: all three guests)
set -euo pipefail

SRC_DIR="/devpool/VMs/images"
STAGE_DIR="/devpool/incus-migration"
OWNER="${OWNER:-rramirez}"

ALL_VMS=(dev-vm-xps download-vm-xps forgejo-ci-runner-vm)
VMS=("$@")
[ "${#VMS[@]}" -eq 0 ] && VMS=("${ALL_VMS[@]}")

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }
}
require_cmd qemu-img
require_cmd virsh
require_cmd tar
require_cmd sudo

sudo mkdir -p "$STAGE_DIR"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for vm in "${VMS[@]}"; do
  src="$SRC_DIR/$vm.qcow2"
  out="$STAGE_DIR/$vm.tar"
  meta="$STAGE_DIR/$vm.metadata.yaml"

  state="$(sudo virsh domstate "$vm" 2>/dev/null || true)"
  if [ "$state" = "running" ]; then
    echo "ERROR: domain '$vm' is still running; shut it down first." >&2
    exit 1
  fi
  [ -f "$src" ] || { echo "ERROR: missing disk image: $src" >&2; exit 1; }

  echo "--- $vm ---"
  sudo qemu-img info "$src" | grep -E "virtual size|disk size" || true

  rm -rf "${tmp:?}/$vm"
  mkdir -p "$tmp/$vm"

  # Compact: drop unused/bloated clusters and re-compress.
  echo "Compacting $vm ..."
  sudo qemu-img convert -c -O qcow2 "$src" "$tmp/$vm/rootfs.img"
  sudo qemu-img info "$tmp/$vm/rootfs.img" | grep -E "virtual size|disk size" || true

  # metadata.yaml is written once so the image fingerprint is stable across runs;
  # a changing fingerprint would make OpenTofu replace the instance.
  if [ ! -f "$meta" ]; then
    sudo tee "$meta" >/dev/null <<EOF
architecture: x86_64
creation_date: $(date +%s)
properties:
  os: NixOS
  release: "25.11"
  description: "xps17 libvirt->incus migration: $vm"
EOF
  fi
  sudo cp "$meta" "$tmp/$vm/metadata.yaml"

  echo "Packing $out ..."
  sudo tar -C "$tmp/$vm" -cf "$out" metadata.yaml rootfs.img
  sudo chown "$OWNER" "$out"
  rm -rf "${tmp:?}/$vm"
done

sudo chmod u=rw,go=r "$STAGE_DIR"/*.tar
echo
echo "Staged Incus VM images:"
ls -lh "$STAGE_DIR"/*.tar
