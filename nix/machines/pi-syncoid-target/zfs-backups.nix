{ config, pkgs, tailnet, ... }:

{
  # sync snapshots from homeserver to tankbak zpool (on driver while testing initial setup)
  environment.systemPackages = with pkgs; [ sanoid ];

  # import tankbak zpool at boot for homeserver syncoid snapshot replication
  boot.zfs.extraPools = [ "tankbak" ];
  boot.zfs.forceImportRoot = false;

  # syncoid runs as root, so it reads system-wide known_hosts, not any user's.
  # This pin is what makes StrictHostKeyChecking safe below.
  programs.ssh.knownHosts.homeserver = {
    hostNames = [ (tailnet.host "homeserver") ];
    # read off homeserver itself and cross-checked against the fleet; rotate if
    # its host key changes
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAI0v0YuUrzQGmOqxPq2/TqmmSOtUpvi5lA6HUHC/I/Y";
  };

  services.syncoid = {
    enable = true;
    interval = "hourly";
    commonArgs = [ "--compress=lzo" ];
    commands = {
      "backup-tank-data" = {
        source = "rramirez@${tailnet.host "homeserver"}:tank/data";
        target = "tankbak/data";
        # left on deliberately: with the pin above there is nothing to trust on
        # first use, and disabling it would let anything answering for that name
        # on the tailnet intercept replication
        extraArgs = [ "--delete-target-snapshots" ];
        sshKey = "/persist/secrets/syncoid-replication/id_ed25519_nop";
      };
    };
    service.serviceConfig.BindReadOnlyPaths = [
      "/persist/secrets/syncoid-replication"
    ];
  };

  # the source is a MagicDNS name, so the tunnel must be up before the sync can
  # resolve it; otherwise the first attempt after boot fails instead of waiting
  systemd.services."syncoid-backup-tank-data" = {
    after = [ "tailscaled-autoconnect.service" "network-online.target" ];
    wants = [ "tailscaled-autoconnect.service" "network-online.target" ];
  };
}
