{ config, lib, pkgs-unstable, ... }:

let
  acmeCertDir = "/var/lib/acme/hy.rueb.dev";
in
{
  # ---------------------------------------------------------------------------
  # Secrets (from the systems-secrets flake input, per-host file)
  # ---------------------------------------------------------------------------
  sops.secrets.vless_uuid = { };
  sops.secrets.reality_private_key = { };
  sops.secrets.reality_short_id = { };
  sops.secrets.hy2_password = { };
  sops.secrets.hy2_obfs_password = { };

  # sing-box must not start before sops has materialized the secrets it reads,
  # nor before the Hysteria2 certificate path exists (acme-<cert>.service writes
  # a self-signed cert first, then order-renew replaces it with the real one).
  systemd.services.sing-box = {
    wants = [ "sops-nix.service" "acme-hy.rueb.dev.service" ];
    after = [ "sops-nix.service" "acme-hy.rueb.dev.service" ];
  };

  # ---------------------------------------------------------------------------
  # Hysteria2 TLS certificate (HTTP-01 via nginx on :80).
  # Shared group so both nginx (8444 SSL listener) and sing-box can read it.
  # ---------------------------------------------------------------------------
  users.groups.hy2-tls = { };
  users.users.sing-box.extraGroups = [ "hy2-tls" ];
  users.users.nginx.extraGroups = [ "hy2-tls" ];

  security.acme.certs."hy.rueb.dev".group = "hy2-tls";
  security.acme.certs."hy.rueb.dev".reloadServices = [ "sing-box.service" ];

  services.nginx.virtualHosts."hy.rueb.dev" = {
    enableACME = true;
    addSSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 80; }
      { addr = "[::0]"; port = 80; }
      { addr = "127.0.0.1"; port = 8444; ssl = true; proxyProtocol = true; }
      { addr = "[::1]"; port = 8444; ssl = true; proxyProtocol = true; }
    ];
    locations."/".return = "404";
  };

  # ---------------------------------------------------------------------------
  # sing-box: VLESS+Reality+Vision (loopback, fronted by HAProxy on :443)
  #           Hysteria2 (public UDP :443)
  # ---------------------------------------------------------------------------
  services.sing-box = {
    enable = true;
    package = pkgs-unstable.sing-box;
    settings = {
      log.level = "warn";

      inbounds = [
        {
          type = "vless";
          tag = "vless-in";
          listen = "127.0.0.1";
          listen_port = 8443;
          users = [
            {
              name = "driver";
              uuid = { _secret = config.sops.secrets.vless_uuid.path; };
              flow = "xtls-rprx-vision";
            }
          ];
          tls = {
            enabled = true;
            server_name = "www.microsoft.com";
            reality = {
              enabled = true;
              handshake = {
                server = "www.microsoft.com";
                server_port = 443;
              };
              private_key = { _secret = config.sops.secrets.reality_private_key.path; };
              short_id = [ { _secret = config.sops.secrets.reality_short_id.path; } ];
            };
          };
        }

        {
          type = "hysteria2";
          tag = "hy2-in";
          listen = "::";
          listen_port = 443;
          obfs = {
            type = "salamander";
            password = { _secret = config.sops.secrets.hy2_obfs_password.path; };
          };
          users = [
            {
              name = "driver";
              password = { _secret = config.sops.secrets.hy2_password.path; };
            }
          ];
          tls = {
            enabled = true;
            certificate_path = "${acmeCertDir}/fullchain.pem";
            key_path = "${acmeCertDir}/key.pem";
          };
          masquerade = "https://news.ycombinator.com/";
        }
      ];

      outbounds = [
        {
          type = "direct";
          tag = "direct";
        }
      ];

      # Resolve destination domains to IPv4 (deterministic egress family).
      dns = {
        strategy = "ipv4_only";
        servers = [
          { type = "udp"; server = "1.1.1.1"; tag = "resolver"; }
        ];
      };

      route = {
        final = "direct";
        default_domain_resolver = { server = "resolver"; };
      };
    };
  };
}
