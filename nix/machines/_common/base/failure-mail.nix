{ config, lib, pkgs, ... }:

# Email an alert when a watched systemd unit fails.
#
# Motivation: matrix-snapshot.service failed 20 times in a row with a 401 and
# nothing anywhere told anyone. Journal entries are not an alerting channel,
# because nobody reads them until after the outage is over.
#
# This is deliberately opt-in per machine and per unit: a laptop that briefly
# loses a mount should not email. Add the units whose silence would be costly.
#
# The transport is `sendmailCmd`, which must read an RFC822 message on stdin and
# take recipients as trailing arguments. Machines with postfix use the sendmail
# wrapper; machines without a mailer use msmtp pointed at the local SMTP server.

let
  cfg = config.rueb.failureMail;
  host = config.networking.hostName;
in
{
  options.rueb.failureMail = {
    enable = lib.mkEnableOption "email alerts when watched systemd units fail";

    recipients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "r3v2@rueb.dev" ];
      description = "Addresses that receive failure alerts.";
    };

    from = lib.mkOption {
      type = lib.types.str;
      default = "root@rueb.dev";
      description = "Envelope sender for alert mail.";
    };

    sendmailCmd = lib.mkOption {
      type = lib.types.str;
      description = ''
        Command that reads an RFC822 message from stdin and accepts recipient
        addresses as trailing arguments, e.g. a sendmail wrapper or msmtp.
      '';
    };

    units = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "matrix-snapshot.service" "my-cronjob.service" ];
      description = "Fully qualified unit names to send mail for when they fail.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.units != [ ];
        message = "rueb.failureMail is enabled but rueb.failureMail.units is empty; nothing would be watched.";
      }
      {
        assertion = cfg.recipients != [ ];
        message = "rueb.failureMail.recipients must not be empty.";
      }
    ];

    # One instance per failed unit, so %i carries the offending unit name.
    # Attached to each watched unit below; systemd has no global OnFailure, so
    # the `units` option is the whole surface of what gets alerted on.
    systemd.services =
      {
        "failure-mail@" = {
          description = "Alert mail for failed unit %i";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = pkgs.writeShellScript "failure-mail" ''
              set -uo pipefail
              unit="%i"
              {
                printf 'From: %s\n' ${lib.escapeShellArg cfg.from}
                printf 'To: %s\n' ${lib.escapeShellArg (lib.concatStringsSep ", " cfg.recipients)}
                printf 'Subject: [ALERT] ${host}: %s entered failed state\n' "$unit"
                printf 'Date: %s\n\n' "$(${pkgs.coreutils}/bin/date -R)"
                printf 'Host: ${host}\nUnit: %s\n\n' "$unit"
                printf -- '--- systemctl status ---\n'
                ${pkgs.systemd}/bin/systemctl status --no-pager -l --lines=40 "$unit" 2>&1 || true
                printf -- '\n--- journal tail ---\n'
                ${pkgs.systemd}/bin/journalctl -u "$unit" --no-pager -n 120 2>&1 || true
              } | ${cfg.sendmailCmd} ${lib.escapeShellArgs cfg.recipients}
            '';
          };
        };
      }
      // lib.genAttrs (map (lib.removeSuffix ".service") cfg.units) (_unit: {
        # %n already carries the unit suffix, so do not append one.
        unitConfig.OnFailure = "failure-mail@%n";
      });
  };
}
