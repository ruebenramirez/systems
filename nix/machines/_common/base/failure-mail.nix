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
  # Indented strings cannot interpolate an Int, and the shell only ever compares text.
  cooldownSecs = toString cfg.cooldown;

  # systemd expands %specifiers in unit-file directives only, never inside the
  # file ExecStart points at, so the failing unit has to arrive as an argument;
  # %i also drops the ".service" suffix, which is put back here.
  # Alert once per outage, then at most once per cooldown while a unit stays
  # broken: matrix-snapshot on a six-hour timer otherwise mails every single run.
  # failure-mail-clear@ drops the marker the moment the unit runs clean again, so
  # the cooldown only ever caps mail inside one ongoing outage.
  failureMailScript = pkgs.writeShellScript "failure-mail" ''
    set -uo pipefail
    unit="''${1:?usage: failure-mail <failed-unit-name-without-suffix>}"
    unit="$unit.service"
    marker="/var/lib/failure-mail/$unit"
    now="$(${pkgs.coreutils}/bin/date +%s)"
    if [ ${cooldownSecs} -gt 0 ] && [ -f "$marker" ]; then
      last="$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || echo 0)"
      since=$(( now - last ))
      if [ "$since" -lt ${cooldownSecs} ]; then
        echo "alert suppressed: last alert ''${since}s ago, cooldown ${cooldownSecs}s"
        exit 0
      fi
    fi
    if {
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
    } | ${cfg.sendmailCmd} ${lib.escapeShellArgs cfg.recipients}; then
      printf '%s\n' "$now" > "$marker"
    else
      # A failed send must not burn the cooldown: the next failure has to mail.
      echo "alert mail failed; no cooldown marker written" >&2
      exit 1
    fi
  '';

  failureMailClearScript = pkgs.writeShellScript "failure-mail-clear" ''
    set -uo pipefail
    unit="''${1:?usage: failure-mail-clear <failed-unit-name-without-suffix>}"
    ${pkgs.coreutils}/bin/rm -f "/var/lib/failure-mail/$unit.service"
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

    cooldown = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 86400;
      description = ''
        Seconds during which a repeat failure of the same unit is not re-mailed.
        The marker is dropped as soon as the unit runs clean again, so this only
        caps mail during one ongoing outage. 0 disables the cap.
      '';
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

    # One instance per failed unit, so %i names the offender. Attached to each
    # watched unit below; systemd has no global OnFailure, so the `units` option
    # is the whole surface of what gets alerted on.
    systemd.services = {
      "failure-mail@" = {
        description = "Alert mail for failed unit %i";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "failure-mail";
          ExecStart = "${failureMailScript} %i";
        };
      };

      "failure-mail-clear@" = {
        description = "End the failure-mail outage window for %i";
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "failure-mail";
          ExecStart = "${failureMailClearScript} %i";
        };
      };
    }
    // lib.genAttrs (map (lib.removeSuffix ".service") cfg.units) (_unit: {
      unitConfig = {
        # %n already carries the unit suffix, so do not append one. OnSuccess
        # closes the outage: without it a unit that heals and breaks again inside
        # the cooldown would go unreported.
        OnFailure = "failure-mail@%n";
        OnSuccess = "failure-mail-clear@%n";
      };
    });
  };
}
