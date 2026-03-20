{ config, pkgs, ... }:

{
  # ---------------------------------------------------------------------------
  # TLS: Wildcard certificate for *.rueb.dev via Cloudflare DNS-01 challenge.
  # Requires a Cloudflare API token with Zone:Zone:Read + Zone:DNS:Edit scope
  # stored at the path below. The stalwart-mail group assignment allows
  # Stalwart to read the issued cert and key without running as root.
  # ---------------------------------------------------------------------------
  security.acme = {
    acceptTerms = true;
    defaults.email = "postmaster@rueb.dev";

    certs."rueb.dev" = {
      domain = "*.rueb.dev";
      dnsProvider = "cloudflare";
      credentialFiles = {
        CLOUDFLARE_DNS_API_TOKEN_FILE = "/persist/secrets/cloudflare-token";
      };
      group = "stalwart-mail";
    };
  };

  # ---------------------------------------------------------------------------
  # Stalwart Mail Server
  # ---------------------------------------------------------------------------
  services.stalwart-mail = {
    enable = true;

    # openFirewall opens: 25, 465, 587, 993.
    # Port 8081 (management) is intentionally excluded — bound to 127.0.0.1 only.
    openFirewall = true;

    # ---------------------------------------------------------------------------
    # Secrets via systemd LoadCredential=
    #
    # The NixOS stalwart-mail module maps this attrset directly to systemd's
    # LoadCredential= directives. Each secret is copied into a tmpfs-backed
    # path at runtime:
    #
    #   /run/credentials/stalwart-mail.service/<key>
    #
    # Pre-deployment: populate source files before first nixos-rebuild switch:
    #
    #   printf 'YOUR_ADMIN_PASSWORD'   > /persist/secrets/stalwart-admin-password
    #   printf 'YOUR_SMTP2GO_USERNAME' > /persist/secrets/smtp2go_username
    #   printf 'YOUR_SMTP2GO_PASSWORD' > /persist/secrets/smtp2go_password
    #
    #   chmod 600 /persist/secrets/stalwart-admin-password \
    #             /persist/secrets/smtp2go_username \
    #             /persist/secrets/smtp2go_password
    #
    #   chown stalwart-mail:stalwart-mail \
    #             /persist/secrets/stalwart-admin-password \
    #             /persist/secrets/smtp2go_username \
    #             /persist/secrets/smtp2go_password
    # ---------------------------------------------------------------------------
    credentials = {
      stalwart_admin_password = "/persist/secrets/stalwart-admin-password";
      smtp2go_username        = "/persist/secrets/smtp2go_username";
      smtp2go_password        = "/persist/secrets/smtp2go_password";
    };

    settings = {

      # Primary hostname for this mail server instance.
      server.hostname = "mail.rueb.dev";

      # Admin UI fallback credentials.
      authentication.fallback-admin = {
        user   = "admin";
        secret = "%{file:/run/credentials/stalwart-mail.service/stalwart_admin_password}%";
      };

      # TLS: reference the wildcard cert issued by security.acme above.
      certificate.main = {
        cert        = "%{file:/var/lib/acme/rueb.dev/cert.pem}%";
        private-key = "%{file:/var/lib/acme/rueb.dev/key.pem}%";
      };

      server.tls = {
        certificate = "main";
        enable      = true;
        implicit    = false; # overridden per-listener below
        version     = "TLSv1.2";
      };

      # -----------------------------------------------------------------------
      # Disable Local DKIM Signing
      # SMTP2GO handles DKIM signing natively via Verified Senders.
      # -----------------------------------------------------------------------
      auth.dkim.sign = false;
      report.dkim.sign = false;
      report.dsn.sign = false;
      report.dmarc.sign = false;
      report.dmarc.aggregate.sign = false;
      report.spf.sign = false;
      report.tls.aggregate.sign = false;
      sieve.trusted.sign = false;

      # -----------------------------------------------------------------------
      # Listeners
      # -----------------------------------------------------------------------
      server.listener = {

        # Inbound SMTP from VPS Postfix over WireGuard.
        smtp = {
          bind                 = [ "[::]:25" ];
          protocol             = "smtp";
          proxy.trusted-networks = [ "10.100.0.5/32" ];
        };

        # Client submission — implicit TLS (SSL/TLS mode in mail clients).
        submissions = {
          bind         = [ "[::]:465" ];
          protocol     = "smtp";
          tls.implicit = true;
        };

        # Client submission — STARTTLS.
        submission = {
          bind         = [ "[::]:587" ];
          protocol     = "smtp";
          tls.implicit = false;
        };

        # IMAP over TLS.
        imaps = {
          bind         = [ "[::]:993" ];
          protocol     = "imap";
          tls.implicit = true;
        };

        # Admin UI — restricted to loopback only.
        management = {
          bind     = [ "127.0.0.1:8081" ];
          protocol = "http";
        };
      };

      # -----------------------------------------------------------------------
      # Outbound relay: SMTP2GO
      #
      # SMTP2GO supports ports 2525, 8025, 587, 80, and 25.
      # DANE and MTA-STS are disabled to avoid validation conflicts.
      # -----------------------------------------------------------------------
      queue.route.smtp2go = {
        type     = "relay";
        address  = "mail.smtp2go.com";
        port     = 2525;
        protocol = "smtp";
        tls = {
          implicit = false;
          dane     = "disable";
          mta-sts  = "disable";
        };
        auth = {
          username = "%{file:/run/credentials/stalwart-mail.service/smtp2go_username}%";
          secret   = "%{file:/run/credentials/stalwart-mail.service/smtp2go_password}%";
        };
      };

      # Local delivery route — no additional parameters required.
      queue.route.local = {
        type = "local";
      };

      # -----------------------------------------------------------------------
      # Routing strategy
      # -----------------------------------------------------------------------
      queue.strategy.route = [
        { "if" = "is_local_domain('', rcpt_domain)"; "then" = "'local'"; }
        { "else" = "'smtp2go'"; }
      ];

      # -----------------------------------------------------------------------
      # Storage backend
      # -----------------------------------------------------------------------
      store.db = {
        type        = "rocksdb";
        path        = "/tank/srv/mail.rueb.dev--stalwart/data";
        compression = "lz4";
      };

      storage = {
        data      = "db";
        fts       = "db";
        blob      = "db";
        lookup    = "db";
        directory = "internal";
      };

    };
  };

  # ---------------------------------------------------------------------------
  # systemd service hardening override.
  # ---------------------------------------------------------------------------
  systemd.services.stalwart-mail.serviceConfig = {
    ReadWritePaths = [
      "/tank/srv/mail.rueb.dev--stalwart"
    ];
  };

  # ---------------------------------------------------------------------------
  # Storage directory setup.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /tank/srv/mail.rueb.dev--stalwart       0750 stalwart-mail stalwart-mail -"
    "d /tank/srv/mail.rueb.dev--stalwart/data  0750 stalwart-mail stalwart-mail -"
    "d /persist/secrets                        0710 root          stalwart-mail -"
    "f /persist/secrets/smtp2go_username           0600 stalwart-mail stalwart-mail -"
    "f /persist/secrets/smtp2go_password           0600 stalwart-mail stalwart-mail -"
    "f /persist/secrets/stalwart-admin-password    0600 stalwart-mail stalwart-mail -"
    "f /persist/secrets/cloudflare-token           0600 root          root          -"
  ];
}
