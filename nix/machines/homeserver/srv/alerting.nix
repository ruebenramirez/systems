{ pkgs, ... }:

{
  # Stalwart is the MX for rueb.dev and binds [::]:25, so alert mail is submitted
  # to its internal listener (port 2525) over loopback. Local recipients are
  # delivered by Stalwart's own queue and never traverse the SMTP2GO outbound
  # route. The internal listener is exempt from SPF/spam checks; port 25 is not.
  environment.etc."msmtprc" = {
    mode = "0644";
    text = ''
      defaults
      tls off
      from root@rueb.dev
      # Stalwart rejects a bare hostname with "550 Invalid EHLO domain", so the
      # EHLO domain has to be a real FQDN (msmtp calls this `domain`).
      domain mail.rueb.dev

      account localhost
      host localhost
      port 2525

      account default : localhost
    '';
  };

  rueb.failureMail = {
    enable = true;
    sendmailCmd = "${pkgs.msmtp}/bin/msmtp --from=root@rueb.dev";

    # Only units whose silence is expensive. ACME is here because renewal
    # failures are otherwise invisible until a certificate expires.
    units = [
      "acme-order-renew-monicaandrueben.com.service"
      "acme-order-renew-monicarosephotography.com.service"
      "acme-order-renew-rueb.dev.service"
      "headscale.service"
      "hermes-backup.service"
      "hosted-sites-backup.service"
      "matrix-backup-freshness.service"
      "matrix-backup.service"
      "sops-install-secrets.service"
      # Fires once per outage, not once per poll: the rescue unit suppresses
      # repeat failures until the pool comes back. See zpool-rescue.sh.
      "zpool-rescue.service"
      # The login shell must never resolve onto tank. This pages long before an
      # outage does, when something re-links a dotfile back into the share.
      "login-shell-anchor-check.service"
    ];
  };
}
