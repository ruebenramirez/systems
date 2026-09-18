{ config, pkgs, ... }:

let
  backupRoot = "/tank/backups/ssdnodes-1";
  # The Linux rsync build cannot preserve creation times. The empty remote
  # path below is the /srv root enforced by rrsync.
  backup = pkgs.writeShellScript "hosted-sites-backup" ''
    export RSYNC_RSH="${pkgs.openssh}/bin/ssh -F /dev/null -i ${config.sops.secrets.hosted_sites_backup_ssh_private_key.path} -o BatchMode=yes -o ConnectTimeout=30 -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts -o IdentitiesOnly=yes -o ServerAliveCountMax=3 -o ServerAliveInterval=30 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/dev/null"

    exec ${pkgs.rsync}/bin/rsync \
      --archive \
      --hard-links \
      --acls \
      --xattrs \
      --atimes \
      --open-noatime \
      --numeric-ids \
      --super \
      --delete-delay \
      --itemize-changes \
      --timeout=600 \
      root@10.100.0.5: \
      ${backupRoot}/srv/
  '';
in
{
  sops.secrets.hosted_sites_backup_ssh_private_key = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  programs.ssh.knownHosts.ssdnodes-1 = {
    hostNames = [ "10.100.0.5" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDNY0yujuHWiB+tE0StHp5mPwSofjtjquE5IHkrQP6AE";
  };

  users.groups.hosted-sites-backup = { };
  users.users.rramirez.extraGroups = [ "hosted-sites-backup" ];

  systemd.services.hosted-sites-backup-directory = {
    description = "Create the hosted sites backup directory";
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/tank";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.coreutils}/bin/install -d -m 2770 -o root -g hosted-sites-backup ${backupRoot}
    '';
  };

  systemd.services.hosted-sites-backup = {
    description = "Pull hosted website files from ssdnodes-1";
    requires = [ "hosted-sites-backup-directory.service" ];
    wants = [ "network-online.target" "wg-quick-wg0.service" ];
    after = [
      "hosted-sites-backup-directory.service"
      "network-online.target"
      "wg-quick-wg0.service"
    ];
    unitConfig.ConditionPathIsMountPoint = "/tank";

    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = backup;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ backupRoot ];
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      LockPersonality = true;
      RestrictRealtime = true;
    };
  };

  systemd.timers.hosted-sites-backup = {
    description = "Pull hosted website files every six hours";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "*-*-* 00/6:00:00";
      Persistent = true;
      Unit = "hosted-sites-backup.service";
    };
  };
}
