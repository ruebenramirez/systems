{ pkgs, tailnet, ... }:
# msmtp + /etc/msmtprc for the workflow's failure mail, submitted to Stalwart on
# homeserver over the tailnet. Stalwart rejects a bare EHLO hostname, hence `domain`.
{
  environment.systemPackages = [ pkgs.msmtp ];

  environment.etc."msmtprc" = {
    mode = "0644";
    text = ''
      defaults
      tls off
      from root@rueb.dev
      domain mail.rueb.dev

      account ci-alert
      host ${tailnet.host "homeserver"}
      port 25

      account default : ci-alert
    '';
  };
}
