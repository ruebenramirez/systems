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
    # This is preferable to referencing /persist/secrets directly because:
    #   - LoadCredential uses read-only tmpfs; no ReadWritePaths exposure needed
    #   - Credentials are inaccessible to other processes under the same UID
    #   - No need to loosen ProtectSystem=strict via additional ReadWritePaths
    #
    # Pre-deployment: populate source files before first nixos-rebuild switch:
    #
    #   printf 'YOUR_ADMIN_PASSWORD'   > /persist/secrets/stalwart-admin-password
    #   printf 'YOUR_SES_USERNAME'     > /persist/secrets/ses_username
    #   printf 'YOUR_SES_PASSWORD'     > /persist/secrets/ses_password
    #
    #   chmod 600 /persist/secrets/stalwart-admin-password \
    #             /persist/secrets/ses_username \
    #             /persist/secrets/ses_password
    #
    #   chown stalwart-mail:stalwart-mail \
    #             /persist/secrets/stalwart-admin-password \
    #             /persist/secrets/ses_username \
    #             /persist/secrets/ses_password
    # ---------------------------------------------------------------------------
    credentials = {
      stalwart_admin_password = "/persist/secrets/stalwart-admin-password";
      ses_username            = "/persist/secrets/ses_username";
      ses_password            = "/persist/secrets/ses_password";
    };

    settings = {

      # Primary hostname for this mail server instance.
      server.hostname = "mail.rueb.dev";

      # Admin UI fallback credentials.
      # This account is used when the directory is unavailable and as the
      # initial login before any directory accounts are created.
      # Secret sourced from systemd credential at runtime.
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
      # Listeners
      # Each listener requires an explicit `protocol` field.
      # `bind` must be a list.
      # Implicit TLS listeners (465, 993) require tls.implicit = true.
      # -----------------------------------------------------------------------
      server.listener = {

        # Inbound SMTP from VPS Postfix over WireGuard.
        # proxy.trusted-networks allows Stalwart to parse the original sender
        # IP from the Proxy Protocol header forwarded by VPS Postfix.
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
        # Access via SSH tunnel: ssh -L 8081:127.0.0.1:8081 user@10.100.0.2
        # Never expose this to [::] or the WireGuard interface.
        management = {
          bind     = [ "127.0.0.1:8081" ];
          protocol = "http";
        };
      };

      # -----------------------------------------------------------------------
      # Outbound relay: Amazon SES
      #
      # IMPORTANT: Use nested attribute syntax (queue.route.ses) NOT quoted
      # dotted strings ("queue.route.ses"). Nix serializes the former as the
      # correct TOML nested table [queue.route.ses]; the latter produces the
      # literal-key form ["queue.route.ses"] which Stalwart's parser rejects.
      #
      # SES on port 587 uses STARTTLS. DANE and MTA-STS are disabled to
      # avoid validation conflicts with AWS certificates.
      # Credentials sourced from systemd LoadCredential= at runtime.
      # -----------------------------------------------------------------------
      queue.route.ses = {
        type     = "relay";
        address  = "email-smtp.us-east-2.amazonaws.com";
        port     = 587;
        protocol = "smtp";
        tls = {
          implicit = false;
          dane     = "disable";
          mta-sts  = "disable";
        };
        auth = {
          username = "%{file:/run/credentials/stalwart-mail.service/ses_username}%";
          secret   = "%{file:/run/credentials/stalwart-mail.service/ses_password}%";
        };
      };

      # Local delivery route — no additional parameters required.
      queue.route.local = {
        type = "local";
      };

      # -----------------------------------------------------------------------
      # Routing strategy
      #
      # Same nested-attribute rule applies: queue.strategy.route not
      # "queue.strategy.route".
      # "if"/"then"/"else" must remain quoted — they are reserved keywords
      # in Nix but are valid TOML keys once serialized.
      # -----------------------------------------------------------------------
      queue.strategy.route = [
        { "if" = "is_local_domain('', rcpt_domain)"; "then" = "'local'"; }
        { "else" = "'ses'"; }
      ];

      # -----------------------------------------------------------------------
      # Storage backend
      #
      # The NixOS stalwart-mail module auto-creates a store named "db" at
      # /var/lib/stalwart-mail/db. We override only the path here to redirect
      # it to the ZFS zpool. Using the module's own "db" store name avoids
      # creating a second orphaned store entry.
      #
      # storage.directory references "internal" — the auto-created
      # directory.internal backend — not the raw store directly.
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
  #
  # The NixOS stalwart-mail module sets ProtectSystem=strict and only grants
  # ReadWritePaths=/var/lib/stalwart-mail. We extend ReadWritePaths here to
  # include the ZFS zpool path only.
  #
  # /persist/secrets is intentionally omitted: all secrets are now consumed
  # via systemd LoadCredential= (services.stalwart-mail.credentials above)
  # and are accessible at /run/credentials/stalwart-mail.service/ at runtime
  # without requiring any ReadWritePaths relaxation.
  # ---------------------------------------------------------------------------
  systemd.services.stalwart-mail.serviceConfig = {
    ReadWritePaths = [
      "/tank/srv/mail.rueb.dev--stalwart"
    ];
  };

  # ---------------------------------------------------------------------------
  # Storage directory setup.
  #
  # /tank/srv/mail.rueb.dev--stalwart — ZFS zpool; all Stalwart mail data
  #   covered by existing sanoid/syncoid snapshot and replication jobs.
  #
  # /persist/secrets — Centralised secrets store. cloudflare-token is owned
  #   by root and consumed only by the ACME service (not Stalwart directly).
  #   The three Stalwart-specific secrets are owned by stalwart-mail and
  #   loaded into /run/credentials/ at service start via LoadCredential=.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /tank/srv/mail.rueb.dev--stalwart       0750 stalwart-mail stalwart-mail -"
    "d /tank/srv/mail.rueb.dev--stalwart/data  0750 stalwart-mail stalwart-mail -"
    "d /persist/secrets                        0710 root          stalwart-mail -"
    "f /persist/secrets/ses_username               0600 stalwart-mail stalwart-mail -"
    "f /persist/secrets/ses_password               0600 stalwart-mail stalwart-mail -"
    "f /persist/secrets/stalwart-admin-password    0600 stalwart-mail stalwart-mail -"
    "f /persist/secrets/cloudflare-token           0600 root          root          -"
  ];
}
