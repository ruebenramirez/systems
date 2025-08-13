{ config, pkgs, ... }:

{
  # Nextcloud service configuration
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud31;  # Latest stable version as of 2025
    hostName = "100.103.101.22:8884";  # Changed from hostname to IP address
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
    configureRedis = true;

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
        "100.103.101.22:8884"
        "localhost"
      ];
      # Overwrite settings for custom port handling
      "overwrite.cli.url" = "http://100.103.101.22:8884/";
      overwritehost = "100.103.101.22:8884";
      overwriteprotocol = "http";
    };
  };

  # PostgreSQL database with custom data location
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/tank/var/lib/postgresql";
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [{
      name = "nextcloud";
      ensureDBOwnership = true;
    }];
  };

  # Redis for caching with custom working directory
  services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
    settings = {
      dir = pkgs.lib.mkForce "/tank/var/lib/redis";
      # Disable RDB snapshots for caching-only use (prevents MISCONF errors)
      save = pkgs.lib.mkForce "";
      stop-writes-on-bgsave-error = pkgs.lib.mkForce "no";
    };
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
          addr = "100.103.101.22";  # Explicitly bind to the target IP
          port = 8884;
        }
      ];
      # Additional server names for IP-based access
      serverAliases = [
        "100.103.101.22"
        "100.103.101.22:8884"
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
    enable = true;
    databases = [ "nextcloud" ];
    location = "/tank/backups/homeserver/postgresql-nextcloud";
  };

  # Create required directories and set permissions
  systemd.tmpfiles.rules = [
    # Main directory structure
    "d /tank/srv 0755 root root -"
    "d /tank/srv/nextcloud 0755 root root -"
    "d /tank/srv/nextcloud/data 0750 nextcloud nextcloud -"
    "d /tank/var/lib/postgresql 0750 postgres postgres -"
    "d /tank/var/lib/redis 0750 redis redis -"
    "d /tank/backups/homeserver/nextcloud/ 0755 root root -"
    "d /tank/backups/homeserver/nextcloud/data 0750 nextcloud nextcloud -"
    "d /tank/backups/homeserver/postgresql 0750 postgres postgres -"
  ];
}
