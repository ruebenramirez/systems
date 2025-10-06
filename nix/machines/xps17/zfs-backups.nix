{ config, pkgs, ... }:

{
  # sync snapshots from homeserver to tankbak zpool (on driver while testing initial setup)
  environment.systemPackages = with pkgs; [ sanoid ];

  # import tankbak zpool at boot for homeserver syncoid snapshot replication
  boot.zfs.extraPools = [ "tankbak" ];

  services.syncoid = {
    enable = true;
    interval = "hourly";
    commonArgs = [ "--compress=lzo" ];
    commands = {
      "backup-tank-data" = {
        source = "rramirez@192.168.1.155:tank/data";
        target = "tankbak/data";
        extraArgs = [ "--delete-target-snapshots" "--sshoption=StrictHostKeyChecking=no" ];
        sshKey = "/persist/secrets/syncoid-replication/id_ed25519_nop";
      };
    };
    service.serviceConfig.BindReadOnlyPaths = [
      "/persist/secrets/syncoid-replication"
    ];
  };
}
