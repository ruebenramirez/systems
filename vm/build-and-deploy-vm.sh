#!/usr/bin/env bash
set -euo pipefail

set -e

VM_NAME="dev-vm-xps"
IMAGE_DEST="/devpool/VMs/images/${VM_NAME}.qcow2"

echo "--- Updating Flake ---"
nix flake update

echo "--- Building VM Image ---"
nix build .#dev-vm-qcow --out-link result-vm

# # Remove existing VM if it exists (Optional: check first)
# if sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
#     sudo virsh destroy "$VM_NAME" || true
#     sudo virsh undefine "$VM_NAME" --remove-all-storage --snapshots-metadata --nvram
# fi

echo "--- Deploying Image to Storage ---"
# Copy out of Nix store to destination
sudo rm -f "$IMAGE_DEST"
sudo cp ./result-vm/nixos.qcow2 "$IMAGE_DEST"
sudo chmod 660 "$IMAGE_DEST"

# Expand to 200GB ceiling (instant on ZFS)
sudo qemu-img resize "$IMAGE_DEST" 200G

echo "--- Provisioning VM ---"
sudo virt-install \
  --name="$VM_NAME" \
  --memory=8192 \
  --vcpus=4 \
  --disk path="$IMAGE_DEST",device=disk,bus=virtio \
  --os-variant=nixos-unstable \
  --boot uefi \
  --network bridge=virbr0,model=virtio \
  --graphics none \
  --noautoconsole \
  --import


echo "Connect with: ssh rramirez@$dev-vm-xps"
