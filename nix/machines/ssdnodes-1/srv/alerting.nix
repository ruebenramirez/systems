{ pkgs, tailnet, ... }:

{
  # Alert mail goes out via msmtp straight to Stalwart's internal listener
  # (port 2525) over the tailnet, bypassing this host's postfix MX relay:
  # unauthenticated fleet mail is exempt from SPF/spam checks on that listener,
  # and transport_maps cannot distinguish local alerts from relayed public mail.
  #
  # Postfix keeps handling this host's relay duty (public MX -> Stalwart :25).
  environment.etc."msmtprc" = {
    mode = "0644";
    text = ''
      defaults
      tls off
      from root@rueb.dev
      # Stalwart rejects a bare hostname with "550 Invalid EHLO domain".
      domain mail.rueb.dev

      account stalwart
      host ${tailnet.host "homeserver"}
      port 2525

      account default : stalwart
    '';
  };

  rueb.failureMail = {
    enable = true;
    sendmailCmd = "${pkgs.msmtp}/bin/msmtp --from=root@rueb.dev";

    units = [
      "acme-order-renew-derp.rueb.dev.service"
      "acme-order-renew-hy.rueb.dev.service"
      "acme-order-renew-matrix.rueb.dev.service"
      "acme-order-renew-monicaandrueben.com.service"
      "acme-order-renew-monicarosephotography.com.service"
      "continuwuity.service"
      "matrix-snapshot.service"
      "sops-install-secrets.service"
    ];
  };
}
