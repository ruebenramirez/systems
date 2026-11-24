{ config, lib, pkgs, ... }:

# Email an alert when a watched systemd unit fails. Journal entries are not an
# alerting channel: matrix-snapshot.service failed 20 times with a 401 and
# nothing told anyone.
#
# Opt-in per machine and per unit -- add only units whose silence is costly.
# `sendmailCmd` must read RFC822 on stdin and take recipients as arguments:
# postfix hosts use the sendmail wrapper, mailer-less ones use msmtp to the
# local SMTP server.

let
  cfg = config.rueb.failureMail;
  host = config.networking.hostName;

  # systemd expands %specifiers in unit-file directives only, never inside the
  # file ExecStart points at, so the failing unit has to arrive as an argument;
  # %i also drops the ".service" suffix, which is put back here.
  failureMailScript = pkgs.writeShellScript "failure-mail" ''
    set -uo pipefail
    unit="''${1:?usage: failure-mail <failed-unit-name-without-suffix>}"
    unit="$unit.service"
    {
      printf 'From: %s\n' ${lib.escapeShellArg cfg.from}
      printf 'To: %s\n' ${lib.escapeShellArg (lib.concatStringsSep ", " cfg.recipients)}
      printf 'Subject: [ALERT] ${host}: %s entered failed state\n' "$unit"
      # MIME-Version + 8bit CTE: unit/journal output carries 8-bit
      # bytes, and without these the spam filter scores the alert
      # MISSING_MIME_VERSION + BAD_CTE_7BIT.
      printf 'Date: %s\n' "$(${pkgs.coreutils}/bin/date -R)"
      printf 'MIME-Version: 1.0\n'
      printf 'Content-Type: text/plain; charset=utf-8\n'
      printf 'Content-Transfer-Encoding: 8bit\n\n'
      printf 'Host: ${host}\nUnit: %s\n\n' "$unit"
      printf -- '--- systemctl status ---\n'
      ${pkgs.systemd}/bin/systemctl status --no-pager -l --lines=40 "$unit" 2>&1 || true
      printf -- '\n--- journal tail ---\n'
      ${pkgs.systemd}/bin/journalctl -u "$unit" --no-pager -n 120 2>&1 || true
    } | ${cfg.sendmailCmd} ${lib.escapeShellArgs cfg.recipients}
  '';
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
      description = "Fully qualified .service unit names to send mail for when they fail.";
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
      {
        # The instance name loses the unit suffix, so only services round-trip:
        # a foo.timer resolves to the nonexistent failure-mail@.timer and would
        # silently never send.
        assertion = builtins.all (lib.hasSuffix ".service") cfg.units;
        message = "every rueb.failureMail.units entry must end in .service.";
      }
    ];

    # One instance per failed unit, so %i names the offender.
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
            ExecStart = "${failureMailScript} %i";
          };
        };
      }
      // lib.genAttrs (map (lib.removeSuffix ".service") cfg.units) (_unit: {
        # %n already carries the unit suffix, so do not append one.
        unitConfig.OnFailure = "failure-mail@%n";
      });
  };
}
