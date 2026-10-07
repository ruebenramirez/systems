{ config, lib, pkgs, ... }:
let
  cfg = config.my.vmNfsServer;

  exportPath = "/tank/vm-nfs-shares";

  parentDirs = [ exportPath ]
    ++ lib.flatten (lib.mapAttrsToList
      (host: _: [ "${exportPath}/${host}" ])
      cfg.shares);

  leafDirs = lib.flatten (lib.mapAttrsToList
    (host: mounts: map (m: "${exportPath}/${host}/${m}") mounts)
    cfg.shares);

  clientExports = lib.listToAttrs (map (c: {
    name = c;
    value = [ "rw" "sync" "no_subtree_check" "no_root_squash" "fsid=0" "crossmnt" ];
  }) cfg.allowedClients);
in
{
  options.my.vmNfsServer = {
    enable = lib.mkEnableOption "VM NFS share server (homeserver tank)";

    shares = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = ''
        Map of host name to list of mount names. Each entry is realized as a
        directory at /tank/vm-nfs-shares/<host>/<mount> on the tank zpool.
      '';
      example = { "dev-vm-xps" = [ "data" ]; };
    };

    allowedClients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "192.168.8.0/24" ];
      description = "NFS clients allowed to mount the share.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Owner uid of the per-mount share directories.";
    };

    gid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = "Owner gid of the per-mount share directories.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.vm-nfs-shares-dirs = {
      wantedBy = [ "nfs-server.service" ];
      before = [ "nfs-server.service" ];
      after = [ "zfs-mount.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script =
        # parent / per-host dirs stay root-owned
        lib.concatMapStrings
          (d: "${pkgs.coreutils}/bin/install -d -m 0755 ${d}\n")
          parentDirs
        # leaf mount dirs are owned by the configured uid:gid (chown is
        # idempotent so it also fixes pre-existing dirs)
        + lib.concatMapStrings
          (d: "${pkgs.coreutils}/bin/install -d -m 0755 ${d}\n"
            + "${pkgs.coreutils}/bin/chown ${toString cfg.uid}:${toString cfg.gid} ${d}\n")
          leafDirs;
    };

    services.nfs.server = {
      enable = true;
      exports."${exportPath}" = clientExports;
    };

    networking.firewall.allowedTCPPorts = [ 2049 ];
  };
}