{ config, lib, pkgs, secretFile, ... }:

let
  # Settings that live in the Stalwart datastore (RocksDB). The generated
  # config file wins over the store at startup (boot.rs merges store keys with
  # or_insert), so file keys override WebUI edits; store keys apply only where
  # the file is silent (e.g. server.allowed-ip, excluded from local-keys).
  # `server add-config` upserts, so re-applying converges.
  #
  # These are 0.15.x settings keys. The 1.0 object/plan API that `stalwart-cli
  # apply` speaks does not exist on the 0.15.5 server nixpkgs ships.
  allowedIps = [
    # Tailnet devices are exempt from HTTP rate limits and auto-bans.
    "100.64.0.0/10"
    "127.0.0.1"
  ];

  # Reject authenticated submissions whose From: mismatches the login. The id
  # matches what the WebUI already wrote; changing it would leave the old script
  # orphaned in the store.
  fromHeaderScript = {
    id = "fromheaderpolicy";
    name = "require valid from header";
    contents = ''
      require ["variables", "envelope", "reject"];
      if allof(not string :is "''${env.authenticated_as}" "",
               not address :all :comparator "i;ascii-casemap" :is "from" "''${envelope.from}") {
        reject "550 5.7.1 The From header must match the address you authenticated as.";
      }
    '';
  };

  # Accounts that need permissions beyond what their role grants.
  accountGrants = [
    # Bypasses per-account request rate limits (rateLimitAuthenticated, IMAP
    # rateLimit) so CalDAV/IMAP sweeps never 429.
    {
      account = "hermes@rueb.dev";
      permissions = [ "unlimited-requests" ];
    }
  ];

  cli = "${pkgs.stalwart-cli}/bin/stalwart-cli";
  curl = "${pkgs.curl}/bin/curl";

  allowedIpLines = lib.concatMapStringsSep "\n"
    (ip: "sw server add-config 'server.allowed-ip.${ip}' ''")
    allowedIps;

  # Principal permissions are not settings keys; they go through the REST API.
  # PATCH takes a list of {action, field, value} updates and is idempotent.
  grantLines = lib.concatMapStringsSep "\n"
    (g: ''
      ${curl} -fsS -X PATCH "$URL/api/principal/${g.account}" \
        -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
        -d '[{"action":"set","field":"enabledPermissions","value":[${
          lib.concatMapStringsSep ", " (p: "\"${p}\"") g.permissions
        }]}]'
    '')
    accountGrants;

  sieveFile = pkgs.writeText "from-header-policy.sieve" fromHeaderScript.contents;
in
{
  # SOPS Secrets
  sops.secrets = {
    smtp2go_username = secretFile "stalwart-server-homeserver" // {
      mode = "0600";
      group = "stalwart-mail";
      owner = "stalwart-mail";
      restartUnits = [ "stalwart.service" ];
    };
    smtp2go_password = secretFile "stalwart-server-homeserver" // {
      mode = "0600";
      group = "stalwart-mail";
      owner = "stalwart-mail";
      restartUnits = [ "stalwart.service" ];
    };
    # Admin API key (WebUI: Account > Credentials > API Keys) for the
    # provisioning oneshot below. Used as a bearer token for curl and decoded
    # to basic auth for stalwart-cli, which cannot take the api_ form.
    stalwart-api-key = secretFile "stalwart-server-homeserver" // {
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

        # Internal submission for fleet-generated mail (Alertmanager, Gatus,
        # msmtp, CI). These hosts submit unauthenticated over the tailnet, so
        # their connecting IP can never satisfy the public SPF record, and
        # relaying through the MX listener made every alert SPF_FAIL/DMARC_NA
        # and land in Junk. On any port other than 25 Stalwart's own defaults
        # skip SPF/DMARC/IPrev verification, and the spam filter is disabled
        # for this listener below -- the trusted-relay exemption keys on the
        # listener, never on the source IP, so public mail on port 25 (which
        # also arrives from the tailnet, via the ssdnodes-1 MX relay) is still
        # fully authenticated and filtered.
        internal = {
          bind     = [ "[::]:2525" ];
          protocol = "smtp";
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

      # Internal listener: fleet-generated mail (Alertmanager, Gatus, msmtp,
      # CI) is submitted unauthenticated over the tailnet, so the connecting
      # IP can never satisfy the public SPF record. Stalwart's own defaults
      # already skip SPF/DMARC/IPrev verification and the EHLO FQDN check on
      # any port other than 25; these two keys relax the non-25 auth
      # requirement and exempt the listener from spam filtering. Public mail
      # (which also arrives over the tailnet, via the ssdnodes-1 MX relay)
      # keeps full authentication and filtering on the smtp listener.
      session.auth.require = [
        { "if" = "listener == 'internal'"; "then" = "false"; }
        { "if" = "local_port != 25"; "then" = "true"; }
        { "else" = "false"; }
      ];
      session.data.spam-filter = [
        { "if" = "listener == 'internal'"; "then" = "false"; }
        { "else" = "true"; }
      ];
      # Pin the relay policy explicitly (same as the 0.15.x default): relaying
      # stays auth-only on every listener, so 2525 can never become an open
      # relay via a store/WebUI edit or a future default change -- file keys
      # override the store.
      session.rcpt.relay = [
        { "if" = "!is_empty(authenticated_as)"; "then" = "true"; }
        { "else" = "false"; }
      ];

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
  # Declarative convergence of datastore-resident settings (allowed IPs,
  # system Sieve, account grants) applied on boot and on every switch.
  # ---------------------------------------------------------------------------
  systemd.services.stalwart-provision = {
    description = "Apply declarative Stalwart configuration";
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
      URL=http://127.0.0.1:8081

      token=$(< "$CREDENTIALS_DIRECTORY/token")
      # stalwart-cli 0.15.x only speaks basic auth, and the api_ token is
      # "api_" + base64("<name>:<secret>"). curl keeps using the bearer form.
      creds=$(printf '%s' "''${token#api_}" | ${pkgs.coreutils}/bin/base64 -d)
      sw() { ${cli} -u "$URL" -c "$creds" "$@" > /dev/null; }

      # Wait for the management API to answer (any HTTP code counts).
      for _ in {1..30}; do
        code=$(${curl} -s -o /dev/null -w '%{http_code}' "$URL" || true)
        [ "$code" != "000" ] && break
        sleep 2
      done

      ${allowedIpLines}

      sw server add-config 'sieve.trusted.scripts.${fromHeaderScript.id}.name' '${fromHeaderScript.name}'
      sw server add-config 'sieve.trusted.scripts.${fromHeaderScript.id}.contents' "$(< ${sieveFile})"

      # Attach the system script to the SMTP DATA stage.
      sw server add-config 'session.data.script' "'${fromHeaderScript.id}'"

      ${grantLines}

      sw server reload-config
    '';
  };

  # Mail protocols only, and only from the tailnet: HTTP listeners stay on
  # loopback and JMAP 8080 comes from bulwark. Forgejo's own submissions need no
  # rule of their own -- app.ini points at mail.rueb.dev, this machine's own
  # tailnet address, so stalwart sees them from that address rather than from a
  # container network. 2525 is the internal alert-submission listener.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 25 465 587 993 2525 4190 ];


  # ---------------------------------------------------------------------------
  # Storage directory setup.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d /tank/srv/mail.rueb.dev--stalwart       0750 stalwart-mail stalwart-mail -"
    "d /tank/srv/mail.rueb.dev--stalwart/data  0750 stalwart-mail stalwart-mail -"
  ];
}
