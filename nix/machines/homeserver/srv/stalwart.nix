{ config, lib, pkgs, systems-secrets, ... }:

let
  # Settings that live in the Stalwart datastore (RocksDB), not in the
  # generated config file. `services.stalwart.settings` only seeds an empty
  # store, so anything changed in the WebUI after first boot must be carried
  # here to survive a rebuild-from-scratch. `stalwart-cli apply` upserts are
  # idempotent: re-applying converges without duplicating objects.
  plan = [
    # Tailnet devices are exempt from HTTP rate limits and auto-bans.
    {
      "@type" = "upsert";
      object = "AllowedIp";
      matchOn = [ "address" ];
      value.tailnet = {
        address = "100.64.0.0/10";
        reason = "Tailscale tailnet: exempt devices from rate limits and auto-bans";
      };
    }

    # Parents first: resolves #dom-rueb to the existing rueb.dev domain id.
    {
      "@type" = "upsert";
      object = "Domain";
      matchOn = [ "name" ];
      value."dom-rueb" = { name = "rueb.dev"; };
    }

    # The hermes service account bypasses per-account request rate limits
    # (rateLimitAuthenticated, IMAP rateLimit) so CalDAV/IMAP sweeps never 429.
    # Merge keeps inherited permissions; only the grant is declared.
    {
      "@type" = "upsert";
      object = "Account";
      matchOn = [ "name" "domainId" ];
      value.hermes = {
        "@type" = "User";
        name = "hermes";
        domainId = "#dom-rueb";
        permissions = {
          "@type" = "Merge";
          enabledPermissions = { unlimitedRequests = true; };
        };
      };
    }

    # Reject authenticated submissions whose From: mismatches the login.
    {
      "@type" = "upsert";
      object = "SieveSystemScript";
      matchOn = [ "name" ];
      value."from-header-policy" = {
        name = "from-header-policy";
        isActive = true;
        contents = ''
          require ["variables", "envelope", "reject"];
          if allof(not string :is "''${env.authenticated_as}" "",
                   not address :all :comparator "i;ascii-casemap" :is "from" "''${envelope.from}") {
            reject "550 5.7.1 The From header must match the address you authenticated as.";
          }
        '';
      };
    }

    # Attach the system script to the SMTP DATA stage.
    {
      "@type" = "update";
      object = "MtaStageData";
      value.script = { "else" = "'from-header-policy'"; };
    }
  ];

  planFile = pkgs.writeText "stalwart-plan.ndjson"
    (lib.concatMapStringsSep "\n" builtins.toJSON plan + "\n");
in
{
  # SOPS Secrets
  sops.secrets = {
    smtp2go_username = {
      mode = "0600";
      group = "stalwart-mail";
      owner = "stalwart-mail";
      restartUnits = [ "stalwart.service" ];
    };
    smtp2go_password = {
      mode = "0600";
      group = "stalwart-mail";
      owner = "stalwart-mail";
      restartUnits = [ "stalwart.service" ];
    };
    # Admin API key (WebUI: Account > Credentials > API Keys). Bearer token
    # for stalwart-cli in the provisioning oneshot below.
    stalwart-api-key = {
      mode = "0400";
    };
  };

  # Grant Stalwart access to read the certificates owned by the shared groups
  users.users.stalwart-mail.extraGroups = [ "ruebdev-wildcard-tls" ];

  # Ensure sops secrets are available before Stalwart starts
  systemd.services.stalwart = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
    serviceConfig.ReadWritePaths = [
      "/tank/srv/mail.rueb.dev--stalwart"
    ];
  };

  # ---------------------------------------------------------------------------
  # Stalwart Mail Server
  # ---------------------------------------------------------------------------
  services.stalwart = {
    enable = true;
    stateVersion = "25.11";
    # Firewall ports are declared explicitly below so loopback HTTP listeners
    # are never included automatically.
    openFirewall = false;

    # ---------------------------------------------------------------------------
    # Secrets via systemd LoadCredential=
    # ---------------------------------------------------------------------------
    credentials = {
      smtp2go_username        = config.sops.secrets.smtp2go_username.path;
      smtp2go_password        = config.sops.secrets.smtp2go_password.path;
    };

    settings = {

      # Primary hostname for this mail server instance.
      server.hostname = "mail.rueb.dev";

      # TLS: Server Name Indication (SNI) setup for multiple domains
      certificate."rueb-dev" = {
        cert        = "%{file:/var/lib/acme/rueb.dev/cert.pem}%";
        private-key = "%{file:/var/lib/acme/rueb.dev/key.pem}%";
      };

      certificate."monicaandrueben-com" = {
        cert        = "%{file:/var/lib/acme/monicaandrueben.com/cert.pem}%";
        private-key = "%{file:/var/lib/acme/monicaandrueben.com/key.pem}%";
      };

      certificate."monicarosephotography-com" = {
        cert        = "%{file:/var/lib/acme/monicarosephotography.com/cert.pem}%";
        private-key = "%{file:/var/lib/acme/monicarosephotography.com/key.pem}%";
      };

      server.tls = {
        certificate = [ "rueb-dev" "monicaandrueben-com" "monicarosephotography-com" ];
        enable      = true;
        implicit    = false; # overridden per-listener below
        version     = "TLSv1.2";
      };

      # SMTP2GO signs DKIM itself via Verified Senders; no global DMARC reports.
      auth.dkim.sign = false;
      report.dkim.sign = false;
      report.dsn.sign = false;

      # Disable sending DMARC Aggregate (RUA) and Failure (RUF) reports globally
      report.dmarc.aggregate-send-frequency = { "else" = "disable"; };
      report.dmarc.failure-send-frequency = { "else" = "disable"; };

      report.dmarc.sign = false;
      report.dmarc.aggregate.sign = false;
      report.dmarc.aggregate.enable = false;
      report.spf.sign = false;
      report.tls.aggregate.sign = false;
      sieve.trusted.sign = false;

      # -----------------------------------------------------------------------
      # Listeners
      # -----------------------------------------------------------------------
      server.listener = {
        # Inbound SMTP from VPS Postfix over headscale VPN.
        smtp = {
          bind                 = [ "[::]:25" ];
          protocol             = "smtp";
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
          tls.implicit = false;
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
          username = "%{file:/run/credentials/stalwart.service/smtp2go_username}%";
          secret   = "%{file:/run/credentials/stalwart.service/smtp2go_password}%";
        };
      };

      # Local delivery route — no additional parameters required.
      queue.route.local.type = "local";

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
  # Declarative convergence of datastore-resident settings (Allowed IPs,
  # system Sieve) via an idempotent stalwart-cli plan applied on boot.
  # ---------------------------------------------------------------------------
  systemd.services.stalwart-provision = {
    description = "Apply declarative Stalwart configuration plan";
    requires = [ "stalwart.service" ];
    after = [ "stalwart.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      LoadCredential = "token:${config.sops.secrets.stalwart-api-key.path}";
    };
    script = ''
      set -euo pipefail
      export STALWART_URL=http://127.0.0.1:8081
      export STALWART_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/token")"

      # Wait for the management API to answer (any HTTP code counts).
      for _ in $(seq 1 30); do
        code=$(${pkgs.curl}/bin/curl -s -o /dev/null -w '%{http_code}' "$STALWART_URL" || true)
        [ "$code" != "000" ] && break
        sleep 2
      done

      ${pkgs.stalwart-cli}/bin/stalwart-cli apply --file ${planFile}
      ${pkgs.stalwart-cli}/bin/stalwart-cli create Action/ReloadSettings
    '';
  };

  # Mail protocols only, on the tailnet plus the forgejo docker bridge (587 for
  # smtp). HTTP listeners stay on loopback; JMAP 8080 comes from bulwark.
  networking.firewall.interfaces = lib.genAttrs
    [ "tailscale0" "br-82bac2f71626" ]
    (_: {
      allowedTCPPorts = [ 25 465 587 993 4190 ];
    });


  # ---------------------------------------------------------------------------
  # Storage directory setup.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /tank/srv/mail.rueb.dev--stalwart       0750 stalwart-mail stalwart-mail -"
    "d /tank/srv/mail.rueb.dev--stalwart/data  0750 stalwart-mail stalwart-mail -"
  ];
}
