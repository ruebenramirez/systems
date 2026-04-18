{ pkgs, roundcube-ident-switch-src, ... }:

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
