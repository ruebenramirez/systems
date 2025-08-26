{ config, pkgs, pkgs-unstable, ... }:

{
  services.freshrss = {
    enable = true;
    baseUrl = "https://freshrss.rueb.dev";
    database.type = "sqlite";
    passwordFile = "/persist/secrets/freshrss-pass";
    defaultUser = "admin";
    package = pkgs-unstable.freshrss;
    virtualHost = "freshrss.rueb.dev";
    webserver = "nginx";
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "freshrss.rueb.dev" = {
        listen = pkgs.lib.mkForce [{
          addr = "127.0.0.1";
          port = 8080;
        }];
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
