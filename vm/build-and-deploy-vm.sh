#!/usr/bin/env bash

set -x

# update the nix flake
#sudo nix flake update

# destroy the existing VM
sudo virsh destroy development-vm
sudo virsh undefine development-vm --remove-all-storage --nvram

# build the image
sudo nix build .#vm-development-qcow

# copy the image into place on tank storage
sudo cp result/nixos.qcow2 /tank/VMs/images/development-vm.qcow2

# Create and start VM
# sudo virt-install \
#       --name=development-vm \
#       --memory=4096 \
#       --vcpus=2 \
#       --disk path=/tank/VMs/images/development-vm.qcow2,device=disk,bus=virtio \
#       --os-variant=generic \
#       --boot uefi \
#       --nographics \
#       --console pty,target_type=virtio \
#       --network bridge=virbr0,model=virtio \
#       --import \
#       --memorybacking=source.type=memfd,access.mode=shared \
#       --filesystem=/tank/vm-storage/,vm-shared,driver.type=virtiofs \
#       --cloud-init user-data=user-data.yml
sudo virt-install \
      --name=development-vm \
      --memory=4096 \
      --vcpus=2 \
      --disk path=/tank/VMs/images/development-vm.qcow2,device=disk,bus=virtio \
      --os-variant=generic \
      --boot uefi \
      --nographics \
      --console pty,target_type=virtio \
      --network bridge=virbr0,model=virtio \
      --import

# TODO find the mac address
VM_MAC_ADDRESS=$(sudo virsh domiflist development-vm | tail -n 2 | cut -w -f 6)
echo "VM MAC: $VM_MAC_ADDRESS"

# TODO: find the IP address
VM_IP_ADDRESS=$(ip neigh | grep "$VM_MAC_ADDRESS" | cut -w -f 1)
# TODO: output the IP Address
echo "IP: $VM_IP_ADDRESS"
