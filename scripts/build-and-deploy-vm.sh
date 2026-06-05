#!/usr/bin/env bash
set -euo pipefail

# Default values
REPLACE_EXISTING="false"
KEEP_ARTIFACTS="false"

# Usage information
usage() {
    echo "Usage: $0 [OPTIONS] <vm-name>"
    echo ""
    echo "VM resources and image sizing are configured declaratively in Nix (my.vmDeploy + disko)."
    echo ""
    echo "Options:"
    echo "  --replace-existing Overwrite an existing image and define/import the VM"
    echo "  --keep-artifacts Keep local build artifacts after deployment"
    exit 1
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Error: required command not found on PATH: $1"
        exit 1
    fi
}

get_vm_ipv4() {
    local vm_name="$1"
    local output=""
    local name=""
    local mac=""
    local protocol=""
    local address=""

    if ! output="$(sudo virsh domifaddr "$vm_name" --source agent 2>/dev/null)"; then
        return 1
    fi

    while read -r name mac protocol address _; do
        if [ "$protocol" = "ipv4" ] && [[ "$address" != 127.* ]]; then
            printf '%s\n' "${address%%/*}"
            return 0
        fi
    done <<< "$output"

    return 1
}

wait_for_vm_ipv4() {
    local vm_name="$1"
    local timeout_seconds=60
    local interval_seconds=5
    local elapsed=0
    local ip=""

    while [ "$elapsed" -lt "$timeout_seconds" ]; do
        if ip="$(get_vm_ipv4 "$vm_name")" && [ -n "$ip" ]; then
            printf '%s\n' "$ip"
            return 0
        fi

        sleep "$interval_seconds"
        elapsed=$((elapsed + interval_seconds))
    done

    return 1
}

print_ssh_config_snippet() {
    local vm_name="$1"
    local host_name="$2"
    local ssh_host_alias="${vm_name}-lan"

    echo "Host ${ssh_host_alias}"
    echo "  HostName ${host_name}"
    echo "  User rramirez"
    echo "  IdentityFile ~/.ssh/id_ed25519"
    echo "  Port 22"
}

validate_local_artifact_path() {
    local path="$1"
    if [ -z "$path" ] || [ "$path" = "/" ] || [ "$path" = "." ] || [ "$path" = ".." ]; then
        echo "Error: refusing unsafe artifact path: '$path'"
        exit 1
    fi
    if [[ "$path" == */* ]]; then
        echo "Error: artifact path must be a basename only: '$path'"
        exit 1
    fi
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        --replace-existing)
            REPLACE_EXISTING="true"
            shift
            ;;
        --keep-artifacts)
            KEEP_ARTIFACTS="true"
            shift
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
OUT_LINK="result-${VM_NAME}-disko"
RAW_IMAGE="${VM_NAME}.raw"
QCOW_IMAGE="${VM_NAME}.qcow2"
DOMAIN_EXISTS="false"
VM_STATE="unknown"
VM_MEMORY=""
VM_VCPUS=""
VM_BRIDGE=""

require_cmd nix
require_cmd qemu-img
require_cmd virsh
require_cmd virt-install
require_cmd sudo

if ! nix eval ".#nixosConfigurations.${VM_NAME}.config.networking.hostName" >/dev/null; then
    echo "Error: No nixosConfigurations.${VM_NAME} found in this flake."
    exit 1
fi

if ! VM_MEMORY="$(nix eval ".#nixosConfigurations.${VM_NAME}.config.my.vmDeploy.memoryMB" 2>/dev/null)"; then
    echo "Error: Missing declarative setting my.vmDeploy.memoryMB for ${VM_NAME}."
    exit 1
fi
if ! [[ "$VM_MEMORY" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid my.vmDeploy.memoryMB for ${VM_NAME}: '$VM_MEMORY'"
    exit 1
fi

if ! VM_VCPUS="$(nix eval ".#nixosConfigurations.${VM_NAME}.config.my.vmDeploy.vcpus" 2>/dev/null)"; then
    echo "Error: Missing declarative setting my.vmDeploy.vcpus for ${VM_NAME}."
    exit 1
fi
if ! [[ "$VM_VCPUS" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid my.vmDeploy.vcpus for ${VM_NAME}: '$VM_VCPUS'"
    exit 1
fi

if ! VM_BRIDGE="$(nix eval --raw ".#nixosConfigurations.${VM_NAME}.config.my.vmDeploy.bridge" 2>/dev/null)"; then
    echo "Error: Missing declarative setting my.vmDeploy.bridge for ${VM_NAME}."
    exit 1
fi
if [ -z "$VM_BRIDGE" ]; then
    echo "Error: Invalid my.vmDeploy.bridge for ${VM_NAME}: bridge is empty"
    exit 1
fi

if [ -e "$IMAGE_DEST" ] && [ "$REPLACE_EXISTING" != "true" ]; then
    echo "Error: $IMAGE_DEST already exists."
    echo "Re-run with --replace-existing after confirming it is safe to replace."
    exit 1
fi

if command -v virsh >/dev/null && sudo virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    DOMAIN_EXISTS="true"
    VM_STATE="$(sudo virsh domstate "$VM_NAME" 2>/dev/null || true)"
    if [ "$VM_STATE" = "running" ]; then
        echo "Error: VM '$VM_NAME' is running. Shut it down before replacing its disk image."
        exit 1
    fi
fi

if [ ! -d "$(dirname "$IMAGE_DEST")" ]; then
    echo "Error: destination directory does not exist: $(dirname "$IMAGE_DEST")"
    exit 1
fi

validate_local_artifact_path "$RAW_IMAGE"
validate_local_artifact_path "$QCOW_IMAGE"
validate_local_artifact_path "$OUT_LINK"

if [ "$DOMAIN_EXISTS" = "true" ] && [ "$REPLACE_EXISTING" != "true" ]; then
    echo "Error: VM domain '$VM_NAME' already exists."
    echo "Re-run with --replace-existing after confirming it is safe to replace the disk image."
    exit 1
fi

if [ "$DOMAIN_EXISTS" = "true" ] && [ "$REPLACE_EXISTING" = "true" ] && [ "$VM_STATE" != "shut off" ]; then
    echo "Error: VM '$VM_NAME' domain exists but is not in a shut off state (state: '$VM_STATE')."
    echo "Shut it down before replacing its disk image."
    exit 1
fi

echo "--- Deployment Preflight ---"
echo "VM: $VM_NAME"
echo "Disk destination: $IMAGE_DEST"
echo "Create/replace mode: $( [ "$REPLACE_EXISTING" = "true" ] && echo "replace" || echo "create" )"
echo "Domain exists: $DOMAIN_EXISTS"
if [ "$DOMAIN_EXISTS" = "true" ]; then
    echo "Domain state: $VM_STATE"
fi
echo "Runtime memory: ${VM_MEMORY}MB"
echo "Runtime vCPUs: ${VM_VCPUS}"
echo "Runtime bridge: ${VM_BRIDGE}"
echo "Local artifact cleanup: $( [ "$KEEP_ARTIFACTS" = "true" ] && echo "disabled" || echo "enabled" )"

echo "--- Updating Flake ---"
echo "Note: this updates flake inputs during deployment and may change lockfile state between runs."
nix flake update

echo "--- Building Disko image script for target: ${VM_NAME} ---"
nix build ".#nixosConfigurations.${VM_NAME}.config.system.build.diskoImagesScript" --out-link "$OUT_LINK"

echo "--- Running Disko image builder ---"
rm -f "$RAW_IMAGE" "$QCOW_IMAGE"
sudo "./${OUT_LINK}"

if [ ! -f "$RAW_IMAGE" ]; then
    echo "Error: expected Disko image was not produced: $RAW_IMAGE"
    exit 1
fi

echo "--- Converting raw image to qcow2 ---"
qemu-img convert -f raw -O qcow2 "$RAW_IMAGE" "$QCOW_IMAGE"
qemu-img info "$QCOW_IMAGE" >/dev/null

echo "--- Deploying Image to Storage ---"
sudo rm -f "$IMAGE_DEST"
sudo cp "$QCOW_IMAGE" "$IMAGE_DEST"
sudo chmod 660 "$IMAGE_DEST"

if [ "$DOMAIN_EXISTS" = "true" ]; then
    echo "--- Existing VM found; replaced disk image only ---"
else
    echo "--- Provisioning VM: $VM_NAME (${VM_MEMORY}MB RAM, ${VM_VCPUS} vCPUs) ---"
    sudo virt-install \
      --name="$VM_NAME" \
      --memory="$VM_MEMORY" \
      --vcpus="$VM_VCPUS" \
      --disk path="$IMAGE_DEST",device=disk,bus=virtio \
      --os-variant=nixos-unstable \
      --boot uefi,firmware.feature0.name=secure-boot,firmware.feature0.enabled=no \
      --network bridge="$VM_BRIDGE",model=virtio \
      --graphics none \
      --noautoconsole \
      --import
fi

if [ "$KEEP_ARTIFACTS" != "true" ]; then
    echo "--- Cleaning Local Build Artifacts ---"
    rm -f "$RAW_IMAGE" "$QCOW_IMAGE" "$OUT_LINK"
fi

echo "--- Deployment Complete ---"
echo "Deployed VM disk: $IMAGE_DEST"
if [ "$KEEP_ARTIFACTS" = "true" ]; then
    echo "Retained local artifacts: $RAW_IMAGE, $QCOW_IMAGE, $OUT_LINK"
else
    echo "Removed local artifacts: $RAW_IMAGE, $QCOW_IMAGE, $OUT_LINK"
fi

echo "--- SSH Config Snippet ---"
if VM_IPV4="$(wait_for_vm_ipv4 "$VM_NAME")"; then
    echo "Add this to ~/.ssh/config:"
    echo ""
    print_ssh_config_snippet "$VM_NAME" "$VM_IPV4"
    echo ""
    echo "Connect with:"
    echo "ssh ${VM_NAME}-lan"
else
    echo "No IPv4 address found from the QEMU guest agent yet."
    echo ""
    echo "Run later:"
    echo "sudo virsh domifaddr $VM_NAME --source agent"
    echo ""
    echo "Then add this to ~/.ssh/config, replacing <ip-address>:"
    echo ""
    print_ssh_config_snippet "$VM_NAME" "<ip-address>"
fi
