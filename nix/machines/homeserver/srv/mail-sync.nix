{ config, lib, pkgs, secretFile, ... }:

let
  # Gmail -> Stalwart sync routing. The addresses are identifiers, not secrets;
  # the passwords they authenticate with live in
  # secrets/mail-sync-server-homeserver.yaml and sops-nix renders each to
  # /run/secrets/<key>, which imapsync reads as a passfile.
  accounts = [
    {
      gmailUser = "ruebendev@gmail.com";
      gmailSecret = "gmail_ruebendev";
      stalwartUser = "r3v2@rueb.dev";
      stalwartSecret = "stalwart_r3v2_rueb_dev";
      enable = true;
    }
    {
      gmailUser = "rueben.ramirez.jr@gmail.com";
      gmailSecret = "gmail_ruebenramirezjr";
      stalwartUser = "r3v2@rueb.dev";
      stalwartSecret = "stalwart_r3v2_rueb_dev";
      enable = true;
    }
    {
      gmailUser = "ruebenramirez@gmail.com";
      gmailSecret = "gmail_ruebenramirez";
      stalwartUser = "r3v2@rueb.dev";
      stalwartSecret = "stalwart_r3v2_rueb_dev";
      enable = true;
    }
    {
      gmailUser = "monicaandrueben@gmail.com";
      gmailSecret = "gmail_monicaandrueben";
      stalwartUser = "us@monicaandrueben.com";
      stalwartSecret = "stalwart_us_monicaandrueben_com";
      enable = true;
    }
    {
      gmailUser = "r37524370@gmail.com";
      gmailSecret = "gmail_r37524370";
      stalwartUser = "us@monicaandrueben.com";
      stalwartSecret = "stalwart_us_monicaandrueben_com";
      enable = true;
    }
    {
      gmailUser = "monicarosephotography@gmail.com";
      gmailSecret = "gmail_monicarosephotography";
      stalwartUser = "monica@monicarosephotography.com";
      stalwartSecret = "stalwart_monica_monicarosephotography_com";
      enable = true;
    }
  ];

  # Only enabled accounts are synced, so only their secrets are declared and
  # decrypted; disabling an account stops it pulling its passwords into the config.
  enabledAccounts = lib.filter (a: a.enable) accounts;

  # Distinct sops keys backing the synced accounts. A Stalwart password is reused
  # across several Gmail accounts, so this set is smaller than the account list.
  secretKeys = lib.unique
    (map (a: a.gmailSecret) enabledAccounts
      ++ map (a: a.stalwartSecret) enabledAccounts);

  # Rendered to the store: no secret values, only addresses and the
  # /run/secrets/<key> paths imapsync reads. Field names match what the script
  # already parses.
  accountConfig = pkgs.writeText "mailsync-accounts.json" (builtins.toJSON
    (map (a: {
      gmail_user = a.gmailUser;
      gmail_pass = config.sops.secrets.${a.gmailSecret}.path;
      stalwart_user = a.stalwartUser;
      stalwart_pass = config.sops.secrets.${a.stalwartSecret}.path;
      active = a.enable;
    }) enabledAccounts));

  gmail-sync-pkg = pkgs.writeShellApplication {
    name = "gmail-sync";

    runtimeInputs = [
      pkgs.imapsync
      pkgs.jq
      pkgs.procps
      pkgs.util-linux
    ];

    text = ''
      #!/usr/bin/env bash

      CONFIG_FILE="${accountConfig}"
      STALWART_HOST="mail.rueb.dev"
      LOCKFILE="/var/lib/mailsync/mailsync.lock"

      exec 9>"$LOCKFILE"
      flock -n 9 || { echo "Another sync run is active; skipping this run."; exit 0; }

      mapfile -t ACCOUNTS < <(jq -c '.[] | select(.active == true)' "$CONFIG_FILE")

      PIDS=()
      FAILED=0

      for row in "''${ACCOUNTS[@]}"; do
          G_USER=$(echo "$row" | jq -r '.gmail_user')
          G_PASS=$(echo "$row" | jq -r '.gmail_pass')
          S_USER=$(echo "$row" | jq -r '.stalwart_user')
          S_PASS=$(echo "$row" | jq -r '.stalwart_pass')

          echo "--- Starting Sync (parallel): $G_USER -> $S_USER ---"

          ( exec imapsync \
              --host1 imap.gmail.com --port1 993 --ssl1 \
              --user1 "$G_USER" --passfile1 "$G_PASS" \
              --host2 "$STALWART_HOST" --port2 993 --ssl2 \
              --user2 "$S_USER" --passfile2 "$S_PASS" \
              --automap \
              --useheader Message-Id \
              --delete1
          ) &

          PIDS+=($!)
      done

      for pid in "''${PIDS[@]}"; do
          wait "$pid" || FAILED=1
      done

      exit $FAILED
    '';
  };
in
{
  users.users.mailsync = {
    isSystemUser = true;
    group = "mailsync";
    extraGroups = [ "stalwart-mail" ];
    home = "/var/lib/mailsync";
    createHome = true;
  };
  users.groups.mailsync = {};

  # One sops secret per distinct password, read by mailsync as an imapsync
  # passfile. Values live in secrets/mail-sync-server-homeserver.yaml.
  sops.secrets = lib.genAttrs secretKeys (key:
    secretFile "mail-sync-server-homeserver" // {
      owner = "mailsync";
      group = "mailsync";
      mode = "0400";
    });

  # cleanup imapsync logs older than 5 days
  systemd.tmpfiles.rules = [
    "d /var/lib/mailsync/LOG_imapsync 0700 mailsync mailsync 2d"
  ];

  systemd.services.gmail-to-stalwart-sync = {
    description = "Sync Gmail to Stalwart via imapsync";
    after = [ "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" "sops-nix.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "mailsync";
      Group = "mailsync";
      WorkingDirectory = "/var/lib/mailsync";
      ExecStart = "${gmail-sync-pkg}/bin/gmail-sync";
      StateDirectory = "mailsync";
      ProtectSystem = "strict";
      PrivateTmp = true;
    };
  };

  systemd.timers.gmail-to-stalwart-sync = {
    description = "Run Gmail sync every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/1";
      Persistent = true;
      Unit = "gmail-to-stalwart-sync.service";
    };
  };
}
