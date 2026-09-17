{ config, pkgs, ... }:

let
  bulwarkDataDir = "/tank/var/lib/bulwark";
  bulwarkImage = pkgs.dockerTools.pullImage {
    imageName = "ghcr.io/bulwarkmail/webmail";
    imageDigest = "sha256:0e8d1339277033b6569a76c6f8192396e6edd66fd917d64d9ed505e8b81dac6d";
    hash = "sha256-my8rWmlS9CglX1JtDJrAHPRNY8S9USpSwD+A0F9frpE=";
    finalImageName = "ghcr.io/bulwarkmail/webmail";
    finalImageTag = "1.9.2";
    os = "linux";
    arch = "amd64";
  };
in
{
  sops.secrets = {
    bulwark-session-secret = { };
    bulwark-admin-password = { };
  };

  sops.templates."bulwark.env" = {
    # ADMIN_PASSWORD only bootstraps the persisted hash when admin.json is absent.
    content = ''
      SESSION_SECRET=${config.sops.placeholder.bulwark-session-secret}
      ADMIN_PASSWORD=${config.sops.placeholder.bulwark-admin-password}
    '';
    mode = "0400";
    restartUnits = [ "podman-bulwark.service" ];
  };

  systemd.tmpfiles.rules = [
    "d ${bulwarkDataDir}             0750 1001 1001 -"
    "d ${bulwarkDataDir}/settings    0750 1001 1001 -"
    "d ${bulwarkDataDir}/admin       0750 1001 1001 -"
    "d ${bulwarkDataDir}/admin-state 0750 1001 1001 -"
  ];

  virtualisation.oci-containers = {
    backend = "podman";
    containers.bulwark = {
      image = "ghcr.io/bulwarkmail/webmail:1.9.2";
      imageFile = bulwarkImage;
      pull = "never";
      autoStart = true;
      environment = {
        HOSTNAME = "0.0.0.0";
        PORT = "3000";
        APP_NAME = "Bulwark Webmail";
        JMAP_SERVER_URL = "https://mail.rueb.dev";
        STALWART_FEATURES = "false";
        SETTINGS_SYNC_ENABLED = "true";
        SETTINGS_DATA_DIR = "/app/data/settings";
        ADMIN_CONFIG_DIR = "/app/data/admin";
        ADMIN_STATE_DIR = "/app/data/admin-state";
        STALWART_ADMIN_ACCESS = "off";
        TRUSTED_PROXY_DEPTH = "1";
        COOKIE_SECURE = "true";
        BULWARK_TELEMETRY = "off";
        BULWARK_UPDATE_CHECK = "off";
      };
      environmentFiles = [ config.sops.templates."bulwark.env".path ];
      ports = [ "127.0.0.1:13380:3000" ];
      volumes = [
        "${bulwarkDataDir}/settings:/app/data/settings"
        "${bulwarkDataDir}/admin:/app/data/admin"
        "${bulwarkDataDir}/admin-state:/app/data/admin-state"
      ];
      podman.sdnotify = "healthy";
      extraOptions = [
        "--health-cmd=wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/api/health"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=3"
        "--health-start-period=10s"
        "--health-on-failure=kill"
      ];
    };
  };

  systemd.services.podman-bulwark = {
    wants = [
      "network-online.target"
      "stalwart.service"
    ];
    after = [
      "network-online.target"
      "stalwart.service"
    ];
    serviceConfig.RestartSec = "10s";
  };

  services.stalwart.settings = {
    server.listener.jmap = {
      bind = [ "127.0.0.1:8080" ];
      protocol = "http";
    };
    server.http.permissive-cors = true;
  };

  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts = {
      "webmail.rueb.dev" = {
        forceSSL = true;
        useACMEHost = "rueb.dev";
        locations."/" = {
          proxyPass = "http://127.0.0.1:13380";
          proxyWebsockets = true;
          extraConfig = "client_max_body_size 10m;";
        };
      };

      "mail.rueb.dev" = {
        forceSSL = true;
        useACMEHost = "rueb.dev";
        locations."/" = {
          proxyPass = "http://127.0.0.1:8080";
          extraConfig = ''
            client_max_body_size 10m;
            proxy_http_version 1.1;
            proxy_buffering off;
            proxy_read_timeout 1h;
            proxy_send_timeout 1h;
            proxy_set_header Connection "";
          '';
        };
      };
    };
  };
}
