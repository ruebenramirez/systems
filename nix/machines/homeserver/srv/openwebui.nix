{ config, pkgs, pkgs-unstable, ... }:

{
  # Upstream credentials. The two API keys are injected together as
  # OPENAI_API_KEYS for the pipe-matched OPENAI_API_BASE_URLS below.
  sops.secrets = {
    openrouter-api-key = { };
    llama-cpp-api-key = { };
  };

  sops.templates."openwebui.env" = {
    content = ''
      OPENAI_API_KEYS=${config.sops.placeholder.openrouter-api-key};${config.sops.placeholder.llama-cpp-api-key}
    '';
    mode = "0400";
    restartUnits = [ "open-webui.service" ];
  };

  services.open-webui = {
    enable = true;
    port = 13379;
    # systemd reads EnvironmentFile as root, so the 0400 template is fine even
    # though the service itself is DynamicUser.
    environmentFile = config.sops.templates."openwebui.env".path;

    package = pkgs-unstable.open-webui.overrideAttrs (_oldAttrs: {
      # NOTE: replace, don't append. Upstream 0.12.3 sets
      #   makeWrapperArgs = [ "--set FRONTEND_BUILD_DIR ..." ];
      # as a single space-joined string, which makeWrapper rejects.
      makeWrapperArgs = [
        "--prefix"
        "PYTHONPATH"
        ":"
        "${pkgs-unstable.python3Packages.makePythonPath [
          pkgs-unstable.python3Packages.youtube-transcript-api
        ]}"
        "--set"
        "FRONTEND_BUILD_DIR"
        "${pkgs.open-webui.frontend}/share/open-webui"
      ];
    });
    environment = {
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
      ENABLE_OLLAMA_API = "False";
      ENABLE_OPENAI_API = "True";
      # Env (incl. the sops-provided OPENAI_API_KEYS) must be authoritative;
      # otherwise the persisted webui.db config overrides it (it held the
      # retired WireGuard URL and an empty key).
      ENABLE_PERSISTENT_CONFIG = "False";
      OPENAI_API_BASE_URLS = "https://openrouter.ai/api/v1;http://fwai0.tailnet.rueb.dev:8080/v1";
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
