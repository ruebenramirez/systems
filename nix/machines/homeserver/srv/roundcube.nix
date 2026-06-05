{ config, pkgs, roundcube-ident-switch-src, ... }:

let
  # The plugin name must be ident_switch to match ident_switch.php
  ident_switch_plugin = pkgs.stdenv.mkDerivation rec {
    pname = "ident_switch";
    version = "5.0.2";
    src = roundcube-ident-switch-src;

    installPhase = ''
      mkdir -p $out/plugins/${pname}
      cp -R ./* $out/plugins/${pname}/
    '';
  };
in
{
  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.roundcube = {
    enable = true;
    hostName = "webmail.rueb.dev";

    package = pkgs.roundcube.withPlugins (plugins: [
      plugins.carddav
      plugins.contextmenu
      plugins.custom_from
      plugins.persistent_login
      plugins.thunderbird_labels
      ident_switch_plugin
    ]);

    # --- POSTGRESQL CONFIGURATION ---
    database.passwordFile = "/persist/secrets/roundcube-db-password";

    configureNginx = true;

    # --- APPLICATION CONFIGURATION ---
    extraConfig = ''
      $config['smtp_host'] = 'tls://mail.rueb.dev';
      $config['smtp_port'] = 587;
      $config['imap_host'] = 'ssl://mail.rueb.dev:993';

      // --- STALWART MANAGESIEVE CONFIGURATION ---
      $config['managesieve_host'] = 'tls://mail.rueb.dev:4190';
      $config['managesieve_auth_type'] = 'PLAIN';
      $config['managesieve_usetls'] = true;
    '';
    plugins = [
      "archive"
      "carddav"
      "contextmenu"
      "custom_from"
      "persistent_login"
      "thunderbird_labels"
      "zipdownload"
      "ident_switch"
      "managesieve"
    ];
  };

  # --- IDENT_SWITCH DATABASE INITIALIZATION ---
  # The ident_switch plugin requires a custom database table to store configuration.
  # This service ensures the schema is created in the PostgreSQL database automatically.
  systemd.services.roundcube-ident-switch-db-init = {
    description = "Initialize Roundcube ident_switch plugin database schema";
    after = [ "postgresql.service" "roundcube-setup.service" ];
    before = [ "phpfpm-roundcube.service" ];
    requires = [ "postgresql.service" "roundcube-setup.service" ];
    requiredBy = [ "phpfpm-roundcube.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };

    script = ''
      PSQL="${config.services.postgresql.package}/bin/psql"

      if ! $PSQL -d roundcube -tAc "SELECT to_regclass('public.ident_switch') IS NOT NULL;" | grep -q t; then
        echo "Creating ident_switch schema..."
        $PSQL -d roundcube -f ${ident_switch_plugin}/plugins/ident_switch/SQL/postgres.initial.sql
      else
        echo "ident_switch schema already exists."
      fi

      echo "Ensuring ident_switch ownership..."
      $PSQL -d roundcube <<'SQL'
ALTER TABLE IF EXISTS public.ident_switch OWNER TO roundcube;
ALTER SEQUENCE IF EXISTS public.ident_switch_id_seq OWNER TO roundcube;
ALTER INDEX IF EXISTS public.ix_ident_switch_user_id OWNER TO roundcube;
ALTER INDEX IF EXISTS public.ix_ident_switch_iid OWNER TO roundcube;
ALTER INDEX IF EXISTS public.ix_ident_switch_parent_id OWNER TO roundcube;
SQL
    '';
  };

  system.activationScripts.roundcube-ident-switch-db-init = ''
    if /run/current-system/systemd/bin/systemctl is-active --quiet postgresql.service; then
      /run/current-system/systemd/bin/systemctl start roundcube-ident-switch-db-init.service || true
    fi
  '';

  # --- NGINX & WILDCARD TLS CONFIGURATION ---
  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."webmail.rueb.dev" = {
      forceSSL = true;
      useACMEHost = "rueb.dev";

      # Explicitly disable the ACME challenge injected by
      # services.roundcube.configureNginx to allow useACMEHost to work.
      enableACME = false;
    };
  };

  # Automatic db backups
  services.postgresqlBackup = {
    databases = [ "roundcube" ];
  };
}
