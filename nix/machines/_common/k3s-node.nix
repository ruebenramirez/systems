# Shared shape of a k3s cluster VM: disk layout, the admin user, and enough
# headroom for kubelet plus its pods. Per-node differences (hostName, and which
# node initialises the cluster) stay in the machine's own configuration.nix.
#
# Sizing (issue #42: "4 vCPU / 8 GiB each, adjust if xps17 headroom requires"):
# 4 vCPU / 6 GiB. xps17 already has 24 GiB committed to its four existing guests
# out of 62 GiB, so three more 8 GiB guests would push the host into swap and
# starve the ZFS arc that serves the Incus qcow2s. 6 GiB per node is the largest
# set that fits without stealing the arc's room.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.my.k3sNode = {
    diskSize = lib.mkOption {
      type = lib.types.str;
      default = "60G";
      description = ''
        Provisioned root disk. Sparse in the qcow2, and pod-local data is
        deliberately small: everything that must survive a node belongs to an
        NFS-backed PVC, not to this disk.
      '';
    };
  };

  config = {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.growPartition = true;

    disko.memSize = 8192;
    disko.imageBuilder.imageFormat = "qcow2";
    disko.devices.disk.main = {
      device = "/dev/vda";
      imageName = config.networking.hostName;
      imageSize = config.my.k3sNode.diskSize;
      type = "disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            type = "EF00";
            size = "512M";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };

    my.monitoring.exporters.node.extraCollectors = [ "processes" ];

    users.users.rramirez = {
      isNormalUser = true;
      uid = 1000;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkQS5ohCDizq24WfDgP/dEOonD/0WfrI0EAZFCyS0Ea"
      ];
    };
    security.sudo.wheelNeedsPassword = false;
  };
}
