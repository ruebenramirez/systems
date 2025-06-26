{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "vm-create" ''
      #!/usr/bin/env bash
      # VM Creation Script
      set -euo pipefail

      VM_NAME=$1
      RAM_MB=$2
      DISK_GB=$3
      ISO_PATH=$4

      echo "Creating VM: $VM_NAME"
      echo "RAM: $RAM_MB MB"
      echo "Disk: $DISK_GB GB"
      echo "ISO: $ISO_PATH"

      # Create disk image
      qemu-img create -f qcow2 /tank/VMs/images/$VM_NAME.qcow2 $DISK_GB

      # Create VM
      virt-install \
        --name=$VM_NAME \
        --memory=$RAM_MB \
        --vcpus=2 \
        --disk path=/tank/VMs/images/$VM_NAME.qcow2,device=disk,bus=virtio \
        --cdrom=$ISO_PATH \
        --os-variant=generic \
        --boot=uefi \
        --nographics \
        --console pty,target_type=virtio \
        --network bridge=virbr0,model=virtio \
        --noautoconsole

      echo "VM $VM_NAME created successfully"
      echo "Connect to console: virsh console $VM_NAME"
    '')

    (writeShellScriptBin "vm-nixos-create" ''
      #!/usr/bin/env bash
      # NixOS VM Creation Script with independent Tailscale
      set -euo pipefail

      VM_NAME=$1
      RAM_MB=''${2:-4096}
      DISK_GB=''${3:-50}

      ISO_URL="https://releases.nixos.org/nixos/25.05/nixos-25.05.804391.b2485d569675/nixos-minimal-25.05.804391.b2485d569675-x86_64-linux.iso"
      ISO_PATH="/tank/VMs/iso/nixos-minimal-latest.iso"

      # Download ISO if not exists
      if [ ! -f "$ISO_PATH" ]; then
        echo "Downloading NixOS ISO..."
        wget -O "$ISO_PATH" "$ISO_URL"
      fi

      vm-create "$VM_NAME" "$RAM_MB" "$DISK_GB" "$ISO_PATH"

      echo ""
      echo "=== VM Created: $VM_NAME ==="
      echo "Next steps:"
      echo "1. Start VM: virsh start $VM_NAME"
      echo "2. Connect: virsh console $VM_NAME"
      echo "3. Install NixOS with independent Tailscale config"
      echo "4. Get Tailscale auth key: vm-tailscale-setup $VM_NAME"
    '')

    (writeShellScriptBin "vm-tailscale-setup" ''
      #!/usr/bin/env bash
      # Tailscale setup helper for VMs
      VM_NAME=$1

      echo "=== Tailscale Setup for VM: $VM_NAME ==="
      echo ""
      echo "1. Generate an auth key at:"
      echo "   https://login.tailscale.com/admin/settings/keys"
      echo ""
      echo "2. Recommended settings:"
      echo "   - Reusable: Yes (for testing)"
      echo "   - Ephemeral: No (for persistent VMs)"
      echo "   - Tags: tag:vm,tag:$VM_NAME"
      echo ""
      echo "3. In your VM's configuration.nix, add:"
      echo "   services.tailscale.enable = true;"
      echo "   networking.hostName = \"$VM_NAME\";"
      echo ""
      echo "4. In the VM console, run:"
      echo "   sudo tailscale up --auth-key=tskey-auth-..."
      echo ""
      echo "5. The VM will appear as '$VM_NAME' in your Tailscale admin"
    '')

    (writeShellScriptBin "vm-list" ''
      #!/usr/bin/env bash
      echo "=== Virtual Machines ==="
      virsh list --all
      echo ""
      echo "=== Storage Pools ==="
      virsh pool-list --all
      echo ""
      echo "=== Networks ==="
      virsh net-list --all
    '')
  ];
}
