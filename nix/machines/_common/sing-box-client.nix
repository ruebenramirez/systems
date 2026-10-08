{ config, lib, pkgs-unstable, ... }:

let
  server = "172.93.51.14";
in
{
  # Secrets come from the per-host systems-secrets file (secrets/driver.yaml).
  sops.secrets.vless_uuid = { };
  sops.secrets.reality_public_key = { };
  sops.secrets.reality_short_id = { };
  sops.secrets.hy2_password = { };
  sops.secrets.hy2_obfs_password = { };
  sops.secrets.clash_api_secret = { };

  # On-demand: never start at boot. `sstunnel on` starts it.
  systemd.services.sing-box = {
    wants = [ "sops-nix.service" ];
    after = [ "sops-nix.service" ];
    wantedBy = lib.mkForce [ ];
  };

  services.sing-box = {
    enable = true;
    package = pkgs-unstable.sing-box;
    settings = {
      log.level = "warn";

      inbounds = [
        {
          type = "tun";
          tag = "tun-in";
          interface_name = "singtun0";
          address = [ "172.19.0.1/30" ];
          mtu = 1500;
          auto_route = true;
          strict_route = true;
          stack = "gvisor";
          route_exclude_address = [
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "169.254.0.0/16"
            "224.0.0.0/4"
            "fd00::/8"
            "fe80::/10"
            "100.64.0.0/10"          # tailnet (headscale)
            "${server}/32"           # the proxy itself
            "2602:ff16:1:0:1:f:0:1/128"
          ];
        }
      ];

      outbounds = [
        {
          type = "vless";
          tag = "vless-out";
          server = server;
          server_port = 443;
          uuid = { _secret = config.sops.secrets.vless_uuid.path; };
          flow = "xtls-rprx-vision";
          packet_encoding = "xudp";
          tls = {
            enabled = true;
            server_name = "www.microsoft.com";
            utls = { enabled = true; fingerprint = "chrome"; };
            reality = {
              enabled = true;
              public_key = { _secret = config.sops.secrets.reality_public_key.path; };
              short_id = { _secret = config.sops.secrets.reality_short_id.path; };
            };
          };
        }

        {
          type = "hysteria2";
          tag = "hy2-out";
          server = server;
          server_port = 443;
          up_mbps = 50;
          down_mbps = 200;
          password = { _secret = config.sops.secrets.hy2_password.path; };
          obfs = {
            type = "salamander";
            password = { _secret = config.sops.secrets.hy2_obfs_password.path; };
          };
          tls = { enabled = true; server_name = "hy.rueb.dev"; };
        }

        { type = "direct"; tag = "direct"; }

        {
          type = "urltest";
          tag = "auto";
          outbounds = [ "vless-out" "hy2-out" ];
          url = "https://cp.cloudflare.com/generate_204";
          interval = "3m";
        }

        {
          type = "selector";
          tag = "proxy";
          outbounds = [ "vless-out" "hy2-out" "auto" ];
          default = "vless-out";
          interrupt_exist_connections = true;
        }
      ];

      dns = {
        servers = [
          # Answers application DNS over the tunnel. Uses an IP, so no bootstrap loop.
          { type = "tls"; server = "1.1.1.1"; tag = "remote"; detour = "proxy"; }
        ];
        final = "remote";
      };

      route = {
        auto_detect_interface = true;
        final = "proxy";
        default_domain_resolver = { server = "remote"; };
        rules = [
          { action = "sniff"; }                              # 1.14: sniff via route action
          { protocol = "dns"; action = "hijack-dns"; }       # capture all plain DNS
          { ip_is_private = true; outbound = "direct"; }
          { ip_cidr = [ "100.64.0.0/10" ]; outbound = "direct"; }  # tailnet
        ];
      };

      experimental.clash_api = {
        external_controller = "127.0.0.1:9090";
        secret = { _secret = config.sops.secrets.clash_api_secret.path; };
      };
    };
  };
}
