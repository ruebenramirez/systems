{ config, lib, ... }:
let
  cfg = config.my.vmNfsClient;
in
{
  options.my.vmNfsClient.mounts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
      options = {
        server = lib.mkOption {
          type = lib.types.str;
          default = "192.168.8.150";
          description = "NFS server address.";
        };
        host = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Host directory name on the server; defaults to this machine's hostName.";
        };
        mountPoint = lib.mkOption {
          type = lib.types.str;
          default = "/mnt/${name}";
          description = "Where the share is mounted locally.";
        };
      };
    }));
    default = { };
    description = "NFS mounts sourced from the homeserver tank VM share tree.";
  };

  config = {
    boot.supportedFilesystems = [ "nfs" ];

    fileSystems = lib.mapAttrs' (name: m:
      lib.nameValuePair m.mountPoint {
        device = "${m.server}:/${if m.host != null then m.host else config.networking.hostName}/${name}";
        fsType = "nfs4";
        options = [
          "nfsvers=4.2"
          "_netdev"
          "hard"
          "nofail"
          "x-systemd.automount"
          "x-systemd.idle-timeout=120"
        ];
      }) cfg.mounts;
  };
}
