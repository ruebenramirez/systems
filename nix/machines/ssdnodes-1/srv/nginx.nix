{ config, pkgs, lib, ... }:

let
  matrixDomain = "matrix.rueb.dev";
in
{
  security.acme = {
    acceptTerms = true;
    defaults = {
      email = "admin@rueb.dev";
    };
  };

  services.nginx = {
    enable = true;

    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    virtualHosts = {
      # Main Matrix server
      "${matrixDomain}" = {
        enableACME = true;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://127.0.0.1:8008";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Host $host;
            client_max_body_size 50M;
          '';
        };
      };

      # Federation endpoint on port 8448
      "${matrixDomain}:8448" = {
        enableACME = false;
        useACMEHost = matrixDomain;
        forceSSL = true;
        listen = [
          { addr = "0.0.0.0"; port = 8448; ssl = true; }
          { addr = "[::]"; port = 8448; ssl = true; }
        ];

        locations."/" = {
          proxyPass = "http://127.0.0.1:8008";
          extraConfig = ''
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Host $host;
            client_max_body_size 50M;
          '';
        };
      };

    };
  };

  users.users.nginx.extraGroups = [ "acme" ];
}
