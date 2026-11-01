{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../_common/base/default.nix
    ../_common/k3s-node.nix
    ../_common/monitoring.nix
    ../_common/nix-deploy-user.nix
    ../_common/qemu-vm-guest.nix
    ../_common/services/k3s-cluster.nix
    ../_common/services/k3s-monitoring.nix
    ../_common/services/k3s-nfs-pvc.nix
    ../_common/tailscale-client.nix
  ];

  networking.hostName = "k3s-2";

  system.stateVersion = "26.05";
}
