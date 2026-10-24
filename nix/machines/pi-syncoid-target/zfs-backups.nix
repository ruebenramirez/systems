{ config, pkgs, tailnet, ... }:

{
  # sync snapshots from homeserver to tankbak zpool (on driver while testing initial setup)
  environment.systemPackages = with pkgs; [ sanoid ];

  # import tankbak zpool at boot for homeserver syncoid snapshot replication
  boot.zfs.extraPools = [ "tankbak" ];
  boot.zfs.forceImportRoot = false;

  # Pin the replication source's host key in the *system-wide* known_hosts.
  # syncoid runs as root under systemd, so it reads /etc/ssh/ssh_known_hosts and
  # never consults any interactive user's ~/.ssh/known_hosts. Pinning here is
  # what makes it safe to stop disabling host key checking below.
  programs.ssh.knownHosts.homeserver = {
    hostNames = [ (tailnet.host "homeserver") ];
    # Read from homeserver itself (/persist/etc/ssh/ssh_host_ed25519_key.pub)
    # over an already-trusted session, and cross-checked against the same key
    # already trusted elsewhere in the fleet. Rotate if homeserver's host key
    # changes.
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
        # StrictHostKeyChecking is deliberately NOT disabled any more. With the
        # pin above there is nothing to trust on first use, and leaving it off
        # would let anything able to answer for that name on the tailnet
        # silently redirect or intercept replication.
        extraArgs = [ "--delete-target-snapshots" ];
        sshKey = "/persist/secrets/syncoid-replication/id_ed25519_nop";
      };
    };
    service.serviceConfig.BindReadOnlyPaths = [
      "/persist/secrets/syncoid-replication"
    ];
  };

  # The source is a MagicDNS name, so the tunnel has to be up before the sync
  # can even resolve it. Without this ordering, a boot where tailscaled has not
  # finished autoconnecting makes the first attempt of the hour fail instead of
  # wait for the tunnel.
  systemd.services."syncoid-backup-tank-data" = {
    after = [ "tailscaled-autoconnect.service" "network-online.target" ];
    wants = [ "tailscaled-autoconnect.service" "network-online.target" ];
  };
}
