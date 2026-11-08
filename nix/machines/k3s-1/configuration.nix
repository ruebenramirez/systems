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
    ../_common/services/k3s-harbor.nix
    ../_common/services/k3s-monitoring.nix
    ../_common/services/k3s-nfs-pvc.nix
    ../_common/tailscale-client.nix
  ];

  networking.hostName = "k3s-1";

  # This node owns cluster initialisation: it is the only one that may run
  # `--cluster-init`, and the other two join through it.
  my.k3sCluster.clusterInit = true;

  system.stateVersion = "26.05";
}
