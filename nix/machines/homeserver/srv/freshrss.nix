{ config, pkgs, pkgs-unstable, ... }:

{
  services.freshrss = {
    enable = true;
    baseUrl = "http://freshrss.internal";
    database.type = "sqlite";
    passwordFile = "/persist/secrets/freshrss-pass";
    defaultUser = "admin";
    package = pkgs-unstable.freshrss;
    virtualHost = "freshrss.internal";
  };

  services.nginx = {
    enable = true;
    virtualHosts = {
      "freshrss.internal" = {
        listen = pkgs.lib.mkForce [{
          addr = "100.101.12.57";
          port = 8080;
        }];
      };
    };
  };
  networking.extraHosts = ''
    100.101.12.57    freshrss.internal
  '';

  networking.firewall.allowedTCPPorts = [ 8080 ];
}
