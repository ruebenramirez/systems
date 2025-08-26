{ config, pkgs, ... }:

{
  # Create VM storage directories
  systemd.tmpfiles.rules = [
    "d /tank/VMs 0755 root libvirtd -"
    "d /tank/VMs/images 0755 root libvirtd -"
    "d /tank/VMs/iso 0755 root libvirtd -"
  ];

  # Configure libvirt storage pool for VM images
  systemd.services.libvirtd.postStart = ''
    # Wait for libvirtd to be ready
    sleep 5

    # Define VM storage pool on ZFS
    ${pkgs.libvirt}/bin/virsh pool-list --all | grep -q vm-storage || \
    ${pkgs.libvirt}/bin/virsh pool-define-as vm-storage dir --target /tank/VMs/images

    # Start and autostart the pool
    ${pkgs.libvirt}/bin/virsh pool-start vm-storage || true
    ${pkgs.libvirt}/bin/virsh pool-autostart vm-storage

    # Define ISO storage pool
    ${pkgs.libvirt}/bin/virsh pool-list --all | grep -q iso-storage || \
    ${pkgs.libvirt}/bin/virsh pool-define-as iso-storage dir --target /tank/VMs/iso

    ${pkgs.libvirt}/bin/virsh pool-start iso-storage || true
    ${pkgs.libvirt}/bin/virsh pool-autostart iso-storage
  '';

  # Optimize ZFS for VM workloads
  boot.postBootCommands = ''
    # Set ZFS properties for VM storage
    ${pkgs.zfs}/bin/zfs set recordsize=64k tank/VMs || true
    ${pkgs.zfs}/bin/zfs set sync=disabled tank/VMs || true
    ${pkgs.zfs}/bin/zfs set compression=lz4 tank/VMs || true
  '';
}
