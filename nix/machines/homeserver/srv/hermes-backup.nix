{ config, pkgs, ... }:

let
  backupRoot = "/tank/backups/hermes-vm-xps";
  # rrsync (hermes-backup-source.nix) pins the remote root to /srv/hermes.
  backup = pkgs.writeShellScript "hermes-backup" ''
    export RSYNC_RSH="${pkgs.openssh}/bin/ssh -F /dev/null -i ${config.sops.secrets.hermes_backup_ssh_private_key.path} -o BatchMode=yes -o ConnectTimeout=30 -o GlobalKnownHostsFile=/etc/ssh/ssh_known_hosts -o IdentitiesOnly=yes -o ServerAliveCountMax=3 -o ServerAliveInterval=30 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=/dev/null"

    exec ${pkgs.rsync}/bin/rsync \
      --archive \
      --delete-delay \
      --itemize-changes \
      --timeout=1800 \
      root@hermes-vm-xps.tailnet.rueb.dev: \
      ${backupRoot}/
  '';
in
{
  sops.secrets.hermes_backup_ssh_private_key = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  programs.ssh.knownHosts.hermes-vm-xps = {
    hostNames = [ "hermes-vm-xps.tailnet.rueb.dev" ];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP4jV43bzjmNq4O59zN7KXBTA7q6fNf8nMsOD4apd6Ae";
  };

  users.groups.hermes-backup = { };
  users.users.rramirez.extraGroups = [ "hermes-backup" ];

  systemd.services.hermes-backup-directory = {
    description = "Create the Hermes backup directory";
    requires = [ "zfs-mount.service" ];
    after = [ "zfs-mount.service" ];
    unitConfig.ConditionPathIsMountPoint = "/tank";

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${pkgs.coreutils}/bin/install -d -m 2770 -o root -g hermes-backup ${backupRoot}
    '';
  };

  systemd.services.hermes-backup = {
    description = "Pull Hermes state backups from hermes-vm-xps";
    requires = [ "hermes-backup-directory.service" ];
    wants = [ "network-online.target" "tailscaled-autoconnect.service" ];
    after = [
      "hermes-backup-directory.service"
      "network-online.target"
      "tailscaled-autoconnect.service"
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

  systemd.timers.hermes-backup = {
    description = "Pull Hermes backups every six hours";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "*-*-* 01/6:00:00";
      Persistent = true;
      Unit = "hermes-backup.service";
    };
  };
}
