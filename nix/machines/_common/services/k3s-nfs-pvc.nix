# Dynamic PVCs on the fleet's existing NFS convention, with Longhorn dropped on
# purpose (issue #42 refinement).
#
# The original plan put Longhorn on top of the tank NFS export with replica
# count 1 -- a replication layer configured to not replicate, standing on
# someone else's filesystem. What the cluster actually needs is a dynamic
# provisioner over an NFS export it can also do ReadWriteMany on, which is what
# csi-driver-nfs is: one pod-per-volume is replaced by one subdirectory per PVC
# under `my.k3sNfsPvc.share`.
#
# Trade-offs worth stating out loud:
#   - No replication: the tank is the only copy, so its own snapshot/backup story
#     (sanoid + syncoid to pi-syncoid-target) is what protects cluster data. It
#     already covers /tank/data, and the export lives inside that dataset.
#   - Shared failure domain: if the tank NFS goes down, every volume's writes
#     stall at once. That is why `TankNfsServerDown` is a cluster-critical alert.
#   - `sync` on the export and `hard` mounts keep acknowledgement honest; the
#     driver inherits both from the server export options.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.k3sNfsPvc;
in
{
  options.my.k3sNfsPvc = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "NFS-backed dynamic PVC provisioning for the k3s cluster.";
    };

    server = lib.mkOption {
      type = lib.types.str;
      default = "192.168.8.150";
      description = ''
        NFS server. Deliberately a LAN address rather than a tailnet name: the
        export is served on the LAN, the tank's export rules are LAN-pinned, and
        pod traffic to it should not depend on the overlay it is storage for.
      '';
    };

    share = lib.mkOption {
      type = lib.types.str;
      default = "/k3s-cluster/pvc";
      description = ''
        Exported directory the driver provisions subdirectories under, as seen
        from the client side: homeserver exports /tank/vm-nfs-shares with
        fsid=0, so the tank path prefix is not part of the NFS namespace and the
        path here is relative to that root (same convention as my.vmNfsClient).
      '';
    };

    storageClassName = lib.mkOption {
      type = lib.types.str;
      default = "nfs";
      description = "StorageClass name; created as the cluster default.";
    };

    chartVersion = lib.mkOption {
      type = lib.types.str;
      default = "4.13.6";
    };

    chartHash = lib.mkOption {
      type = lib.types.str;
      default = "sha256-S0cfsTS/6k/Ko9wzQqZ6zWRkMbdGxnPJeDJzU9tdIto=";
      description = "Hash of the csi-driver-nfs chart tarball.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.k3s.autoDeployCharts.csi-driver-nfs = {
      repo = "https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts";
      name = "csi-driver-nfs";
      version = cfg.chartVersion;
      hash = cfg.chartHash;
      targetNamespace = "kube-system";
      values = {
        driver = {
          name = "nfs.csi.k8s.io";
          # The controller runs the `csi-provisioner` sidecar which is built
          # for stateless deployments; Recreate avoids two provisioners racing.
          controller = {
            replicas = 2;
            strategy.type = "Recreate";
          };
        };
        # The driver calls mount.nfs on the node, so the node must have an NFS
        # client -- k3s-cluster.nix enables boot.supportedFilesystems for that.
        storageClass = {
          create = true;
          name = cfg.storageClassName;
          # csi-driver-nfs has no `isDefaultClass` value: the annotation is the
          # only way to make this the cluster default.
          annotations = {
            "storageclass.kubernetes.io/is-default-class" = "true";
          };
          reclaimPolicy = "Retain";
          allowVolumeExpansion = true;
          # `Retain` rather than `Delete`: on a shared export, deleting the last
          # copy of a volume's bytes because a PVC was `kubectl delete`'d is not
          # a failure mode worth having. The leftover PV has to be reclaimed by
          # hand, which is the point.
          mountOptions = [
            "nfsvers=4.2"
            "hard"
            "nolock"
            "timeo=600"
            "retrans=3"
          ];
          parameters = {
            server = cfg.server;
            share = cfg.share;
          };
        };
      };
    };
  };
}
