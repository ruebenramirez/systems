{ pkgs, ... }:

let
  partsStock = pkgs.callPackage ../../../pkgs/parts-stock/package.nix { };
in
{
  # "Inventory Check" -- the parts-stock barcode inventory PWA, served as the
  # static bundle it is at https://inventory-demo.rueb.dev.
  #
  # Ingress is the same shape as matrix.nix: HAProxy :443 (SNI) -> nginx
  # 127.0.0.1:8444 with PROXY protocol, and ACME HTTP-01 against the public :80
  # listener -- so inventory-demo.rueb.dev has to stay grey-cloud (DNS-only),
  # or the challenge gets Cloudflare's edge instead of this host.
  services.nginx.virtualHosts."inventory-demo.rueb.dev" = {
    enableACME = true;
    forceSSL = true;

    listen = [
      {
        addr = "0.0.0.0";
        port = 80;
      }
      {
        addr = "[::0]";
        port = 80;
      }
      {
        addr = "127.0.0.1";
        port = 8444;
        ssl = true;
        proxyProtocol = true;
      }
      {
        addr = "[::1]";
        port = 8444;
        ssl = true;
        proxyProtocol = true;
      }
    ];

    root = partsStock;

    # The service worker is stale-while-revalidate and precaches the whole
    # same-origin bundle, so no network is needed once the PWA is loaded; a
    # long-lived HTTP cache here would only delay updates reaching the SW.
    locations."/" = {
      extraConfig = ''
        add_header Cache-Control "no-cache";
      '';
    };
  };
}
