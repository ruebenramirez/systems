{ config, pkgs, ... }:

{
  # Grant Stalwart access to read the certificates owned by the shared groups
  users.users.stalwart-mail.extraGroups = ["ruebdev-wildcard-tls"];

  # ---------------------------------------------------------------------------
  # Stalwart Mail Server
  # ---------------------------------------------------------------------------
  services.stalwart-mail = {
    enable = true;

    # openFirewall opens: 25, 465, 587, 993.
    # Port 8081 (management) is intentionally excluded — bound to 127.0.0.1 only.
    # Note: Port 4190 is NOT opened by default by openFirewall = true.
    openFirewall = true;

    # ---------------------------------------------------------------------------
    # Secrets via systemd LoadCredential=
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

      # TLS: Server Name Indication (SNI) setup for multiple domains
      certificate."rueb-dev" = {
        cert        = "%{file:/var/lib/acme/rueb.dev/cert.pem}%";
        private-key = "%{file:/var/lib/acme/rueb.dev/key.pem}%";
      };

      certificate."monicaandrueben-com" = {
        cert        = "%{file:/var/lib/acme/monicaandrueben.com/cert.pem}%";
        private-key = "%{file:/var/lib/acme/monicaandrueben.com/key.pem}%";
      };

      server.tls = {
        certificate = [ "rueb-dev" "monicaandrueben-com" ];
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

        # --- MANAGESIEVE LISTENER ---
        sieve = {
          bind         = [ "[::]:4190" ];
          protocol     = "managesieve";
          tls.implicit = false; # Matches tls:// in Roundcube config
        };

        # Admin UI — restricted to loopback only.
        management = {
          bind     = [ "127.0.0.1:8081" ];
          protocol = "http";
        };
      };

      # -----------------------------------------------------------------------
      # Outbound relay: SMTP2GO
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
  # Firewall: Open ManageSieve port
  # ---------------------------------------------------------------------------
  networking.firewall.allowedTCPPorts = [ 4190 ];

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
