{ config, pkgs, ... }:

let
  gmail-sync-pkg = pkgs.writeShellApplication {
    name = "gmail-sync";

    runtimeInputs = [
      pkgs.imapsync
      pkgs.jq
      pkgs.procps
    ];

    text = ''
      #!/usr/bin/env bash

      CONFIG_FILE="/persist/secrets/mailsync/accounts.json"
      STALWART_HOST="mail.rueb.dev"

      if [[ ! -f "$CONFIG_FILE" ]]; then
          echo "Error: Configuration file not found at $CONFIG_FILE"
          exit 1
      fi

      jq -c '.[] | select(.active == true)' "$CONFIG_FILE" | while read -r row; do
          G_USER=$(echo "$row" | jq -r '.gmail_user')
          G_PASS=$(echo "$row" | jq -r '.gmail_pass')
          S_USER=$(echo "$row" | jq -r '.stalwart_user')
          S_PASS=$(echo "$row" | jq -r '.stalwart_pass')

          echo "--- Starting Sync: $G_USER -> $S_USER ---"

          imapsync \
            --host1 imap.gmail.com --port1 993 --ssl1 \
            --user1 "$G_USER" --passfile1 "$G_PASS" \
            --host2 "$STALWART_HOST" --port2 993 --ssl2 \
            --user2 "$S_USER" --passfile2 "$S_PASS" \
            --folder INBOX \
            --folder "[Gmail]/Sent Mail" \
            --folder "[Gmail]/Drafts" \
            --useheader "Message-Id" \
            --regextrans2 's/^INBOX$/INBOX/' \
            --regextrans2 's/^\[Gmail\]\/Sent Mail$/Sent/' \
            --regextrans2 's/^\[Gmail\]\/Drafts$/Drafts/' \
            --delete1
      done
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

  # cleanup imapsync logs older than 5 days
  systemd.tmpfiles.rules = [
    "d /var/lib/mailsync/LOG_imapsync 0700 mailsync mailsync 5d"
  ];

  systemd.services.gmail-to-stalwart-sync = {
    description = "Sync Gmail to Stalwart via imapsync";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "mailsync";
      Group = "mailsync";
      WorkingDirectory = "/var/lib/mailsync";
      ExecStart = "${gmail-sync-pkg}/bin/gmail-sync";
      ReadOnlyPaths = [ "/persist/secrets/mailsync" ];
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
