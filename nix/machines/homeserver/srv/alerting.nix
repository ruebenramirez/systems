{ pkgs, ... }:

{
  # Stalwart is the MX for rueb.dev and binds [::]:25, so alert mail is submitted
  # to it over loopback. Local recipients are delivered by Stalwart's own queue
  # and never traverse the SMTP2GO outbound route.
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
      port 25

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
    ];
  };
}
