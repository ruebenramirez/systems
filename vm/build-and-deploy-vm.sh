#!/usr/bin/env bash
set -euo pipefail

# Default values
DISK_SIZE="200"
MEMORY="512"

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] <vm-name>"
    echo ""
    echo "Options:"
    echo "  --size    Disk size in GB. Default: 200"
    echo "  --memory  Memory in MB. Default: 512"
    exit 1
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --size)
            DISK_SIZE="$2"
            if ! [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
                echo "Error: --size requires a numeric value."
                exit 1
            fi
            shift 2
            ;;
        --memory)
            MEMORY="$2"
            if ! [[ "$MEMORY" =~ ^[0-9]+$ ]]; then
                echo "Error: --memory requires a numeric value."
                exit 1
            fi
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            break # Stop parsing flags; the rest is the VM name
            ;;
    esac
done

# Check if VM name is provided after flags
if [ $# -eq 0 ]; then
    echo "Error: No VM name provided."
    usage
fi

VM_NAME="$1"
IMAGE_DEST="/devpool/VMs/images/${VM_NAME}.qcow2"

echo "--- Updating Flake ---"
nix flake update

echo "--- Building VM Image for target: .#${VM_NAME}-image ---"
nix build ".#${VM_NAME}-image" --out-link "result-${VM_NAME}"

echo "--- Deploying Image to Storage ---"
sudo rm -f "$IMAGE_DEST"
sudo cp "./result-${VM_NAME}/nixos.qcow2" "$IMAGE_DEST"
sudo chmod 660 "$IMAGE_DEST"

echo "--- Resizing Image to ${DISK_SIZE}G ---"
sudo qemu-img resize "$IMAGE_DEST" "${DISK_SIZE}G"

echo "--- Provisioning VM: $VM_NAME (${MEMORY}MB RAM) ---"
sudo virt-install \
  --name="$VM_NAME" \
  --memory="$MEMORY" \
  --vcpus=4 \
  --disk path="$IMAGE_DEST",device=disk,bus=virtio \
  --os-variant=nixos-unstable \
  --boot uefi \
  --network bridge=br0,model=virtio \
  --graphics none \
  --noautoconsole \
  --import

echo "--- Deployment Complete ---"
echo "Connect with: ssh rramirez@$VM_NAME"
