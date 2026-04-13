{ config, pkgs, pkgs-unstable, ... }:

{
  services.open-webui = {
    enable = true;
    port = 13379;
    package = pkgs-unstable.open-webui.overrideAttrs (oldAttrs: {
      makeWrapperArgs = (oldAttrs.makeWrapperArgs or []) ++ [
        "--prefix PYTHONPATH : ${pkgs-unstable.python3Packages.makePythonPath [
          pkgs-unstable.python3Packages.youtube-transcript-api
        ]}"
      ];
    });
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      OLLAMA_API_BASE_URL = "http://10.100.0.31:11434";
    };
  };


  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."ai.rueb.dev" = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:13379";
        proxyWebsockets = true;
      };
    };
  };

}
