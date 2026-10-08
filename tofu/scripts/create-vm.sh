#!/usr/bin/env bash
# Register the image, create the instance with the Incus CLI, and adopt it into
# OpenTofu state (the provider's create path is unreliable for large VM disks,
# and the CLI can't create a VM without a profile -> vm-base).
#
# Run after `build-incus-image.sh <vm>` and adding the VM to tofu/locals.tf.
#
# Usage: create-vm.sh <vm>
set -euo pipefail

vm="${1:?usage: create-vm.sh <vm>}"
cd "$HOME/code/systems/tofu"
export TF_IN_AUTOMATION=1

# Read cpu/mem/mac from locals.tf via `tofu console` (works before apply).
vals="$(echo "join(\",\", [tostring(local.vms[\"$vm\"].vcpus), local.vms[\"$vm\"].memory, local.vms[\"$vm\"].mac])" \
  | tofu console 2>/dev/null | tail -1 | tr -d '"')"
IFS=',' read -r vcpus mem mac <<<"$vals"
[ -n "$vcpus" ] && [ -n "$mem" ] && [ -n "$mac" ] || { echo "ERROR: could not read spec for $vm from locals.tf" >&2; exit 1; }

echo "Registering image for $vm ..."
tofu apply -auto-approve -input=false -target="incus_image.vm[\"$vm\"]"

fp="$(tofu state show "incus_image.vm[\"$vm\"]" | awk '/fingerprint/{gsub(/"/,"",$3); print $3; exit}')"
[ -n "$fp" ] || { echo "ERROR: no fingerprint for $vm in state" >&2; exit 1; }
echo "image fingerprint: $fp"

incus init local:"$fp" "$vm" --vm -p vm-base
incus config set "$vm" limits.cpu="$vcpus"
incus config set "$vm" limits.memory="$mem"
incus config device add "$vm" eth0 nic nictype=bridged parent=br0 hwaddr="$mac"
incus start "$vm"

tofu import "incus_instance.vm[\"$vm\"]" "$vm,image=$fp"
echo "=== tofu plan (expect no changes) ==="
tofu plan -input=false