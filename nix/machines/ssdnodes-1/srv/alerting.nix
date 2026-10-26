{ ... }:

{
  # Postfix is already installed here as the rueb.dev MX relay, so its sendmail
  # wrapper is the alert transport.
  #
  # Caveat observed while testing: mail submitted from this host fails SPF, DKIM
  # and DMARC checks on the Stalwart side (it is accepted as ham today, but a
  # stricter policy would start dropping alerts). Worth signing outbound or
  # marking the tailnet relay trusted in Stalwart if alerts ever go missing.
  rueb.failureMail = {
    enable = true;
    sendmailCmd = "/run/wrappers/bin/sendmail -i -f root@rueb.dev";

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
