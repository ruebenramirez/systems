{ config, lib, pkgs, ... }:
{
  # KVM support (nested enabled for VMs-in-VMs e.g. k3d/kind).
  boot.kernelModules = [ "kvm-intel" "tun" ];
  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm ignore_msrs=1
  '';

  # Incus on NixOS requires the nftables firewall backend.
  networking.nftables.enable = true;

  virtualisation.incus = {
    enable = true;
    # incus-lts 7.0.1 segfaulted in its raft/cowsql DB during large VM
    # instance creation; use the mainline incus (7.5.x) for the fixes.
    package = pkgs.incus;
  };

  environment.systemPackages = with pkgs; [
    incus
    opentofu
    qemu-utils   # qemu-img, used by tofu/scripts/stage-libvirt-disks.sh
  ];

  users.users.rramirez.extraGroups = [ "incus-admin" ];
}
