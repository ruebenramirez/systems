{ config, pkgs, ... }:

{
  # Nextcloud service configuration
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud31;  # Latest stable version as of 2025
    hostName = "100.101.12.57:8884";  # Changed from hostname to IP address
    https = false;  # Disable HTTPS for HTTP-only on port 8884
    maxUploadSize = "16G";

    # Custom data directory on /tank/srv
    datadir = "/tank/srv/nextcloud/data";

    # Database configuration - PostgreSQL recommended for production
    database.createLocally = true;
    config = {
      dbtype = "pgsql";
      dbuser = "nextcloud";
      dbhost = "/run/postgresql";
      dbname = "nextcloud";
      adminpassFile = "/persist/nextcloud/admin-pass";
      adminuser = "admin";
      overwriteProtocol = "http";  # Force HTTP protocol
      defaultPhoneRegion = "US";
      trustedProxies = [ "127.0.0.1" "::1" ];
    };

    # Redis for caching (automatically configured)
    caching.redis = true;
    settings.redis = {
      host = "127.0.0.1";
      post = 6379;
      dbindex = 2; #dedicate
      timeout = 1.5;
    };

    # Applications to install and enable
    autoUpdateApps.enable = true;
    extraAppsEnable = true;
    extraApps = with config.services.nextcloud.package.packages.apps; {
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/pkgs/servers/nextcloud/packages/nextcloud-apps.json
      inherit
        calendar
        contacts
        mail
        notes
        tasks
        deck
        files_mindmap
        gpoddersync
        maps
        music
        nextpod
        onlyoffice
        phonetrack
        spreed
        whiteboard;
    };

    # Performance and security settings
    phpOptions = {
      "opcache.interned_strings_buffer" = "23";
      "opcache.memory_consumption" = "128";
      "opcache.max_accelerated_files" = "10000";
      "opcache.revalidate_freq" = "1";
      "opcache.fast_shutdown" = "1";
    };

    settings = {
      maintenance_window_start = 2;  # 02:00 maintenance window
      default_phone_region = "US";
      filelocking.enabled = true;
      # Redis configuration is handled automatically by configureRedis = true
      mail_smtpmode = "sendmail";
      mail_sendmailmode = "smtp";
      # Trusted domains configuration for IP access
      trusted_domains = [
        "100.101.12.57:8884"
        "localhost"
      ];
      # Overwrite settings for custom port handling
      "overwrite.cli.url" = "http://100.101.12.57:8884/";
      overwritehost = "100.101.12.57:8884";
      overwriteprotocol = "http";
    };
  };

  # PostgreSQL database with custom data location
  services.postgresql = {
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [{
      name = "nextcloud";
      ensureDBOwnership = true;
    }];
  };

  # Nginx configuration for custom port 8884 and IP address
  services.nginx = {
    enable = true;
    virtualHosts."${config.services.nextcloud.hostName}" = {
      listen = [
        {
          addr = "0.0.0.0";  # Listen on all interfaces
          port = 8884;
        }
        {
          addr = "100.101.12.57";  # Explicitly bind to the target IP
          port = 8884;
        }
      ];
      # Additional server names for IP-based access
      serverAliases = [
        "100.101.12.57"
        "100.101.12.57:8884"
      ];
      # Note: .well-known locations are automatically configured by the Nextcloud module
    };
  };

  # Systemd service dependencies
  systemd.services."nextcloud-setup" = {
    requires = [ "postgresql.service" "redis-nextcloud.service" ];
    after = [ "postgresql.service" "redis-nextcloud.service" ];
  };

  # Firewall configuration
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 8884 ];  # Custom Nextcloud port
  };

  # Automatic db backups
  services.postgresqlBackup = {
    databases = [ "nextcloud" ];
  };

  # Create required directories and set permissions
  # systemd.tmpfiles.rules = [
  #   # Main directory structure
  #   "d /tank/srv 0755 root root -"
  #   "d /tank/srv/nextcloud 0755 root root -"
  #   "d /tank/srv/nextcloud/data 0750 nextcloud nextcloud -"
  #   "d /tank/backups/homeserver/nextcloud/ 0755 root root -"
  #   "d /tank/backups/homeserver/nextcloud/data 0750 nextcloud nextcloud -"
  # ];
}
