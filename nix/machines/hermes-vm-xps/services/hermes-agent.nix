{ config, lib, pkgs, ... }:

let
  # `nousresearch/hermes-agent:stable`, digest-pinned (amd64 manifest). Verified
  # 2026-10-09: Python 3.14.7, `import olm` OK (no pre-3.14 fallback needed),
  # runs as uid/gid 10000, state under HERMES_HOME=/opt/data.
  hermesImage = pkgs.dockerTools.pullImage {
    imageName = "nousresearch/hermes-agent";
    imageDigest = "sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784";
    hash = "sha256-DijWDU+wh7FBnF3hFPZKJhuxc8YkaEtPNGVrqZw7VUY=";
    finalImageName = "nousresearch/hermes-agent";
    finalImageTag = "stable";
    os = "linux";
    arch = "amd64";
  };

  # Encrypted room id, captured at bootstrap; whitelist so Hermes only answers
  # in that room.
  matrixRoom = "!G9nnRAWVcjY2V2pR0VDTOtUnwcToZy37SDFnRtktutg";

  # Managed scope (`/etc/hermes`), deep-merged over the user config and wins.
  # The dashboard refuses to bind 0.0.0.0 unless `dashboard.basic_auth` is
  # configured here (env vars alone do not register the auth provider).
  managedConfig = ''
    dashboard:
      basic_auth:
        username: ${config.sops.placeholder.hermes-dashboard-basic-auth-username}
        password: ${config.sops.placeholder.hermes-dashboard-basic-auth-password}
        secret: ${config.sops.placeholder.hermes-dashboard-basic-auth-secret}
    providers:
      halogen:
        base_url: http://fwai0.tailnet.rueb.dev:8731/v1
        key_env: HALOGEN_API_KEY
        api_mode: chat_completions
        models:
          halogen-qwen3.8-flash-next: {}
  '';

  envFile = ''
    API_SERVER_KEY=${config.sops.placeholder.hermes-api-server-key}
    OPENROUTER_API_KEY=${config.sops.placeholder.openrouter-api-key}
    # The halogen engine runs without auth (HALOGEN_API_KEY unset); this is a
    # static placeholder to satisfy the provider's key_env field.
    HALOGEN_API_KEY=halogen
    MATRIX_ACCESS_TOKEN=${config.sops.placeholder.matrix-access-token}
    MATRIX_RECOVERY_KEY=${config.sops.placeholder.matrix-recovery-key}
  '';
in
{
  sops.secrets = {
    hermes-dashboard-basic-auth-username = { };
    hermes-dashboard-basic-auth-password = { };
    hermes-dashboard-basic-auth-secret = { };
    hermes-api-server-key = { };
    openrouter-api-key = { };
    matrix-access-token = { };
    matrix-recovery-key = { };
  };

  sops.templates."hermes-managed-config" = {
    content = managedConfig;
    uid = 10000;
    gid = 10000;
    mode = "0400";
    restartUnits = [ "podman-hermes.service" ];
  };

  sops.templates."hermes.env" = {
    content = envFile;
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "podman-hermes.service" ];
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/hermes 0700 10000 10000 -"
  ];

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.hermes = {
    image = "nousresearch/hermes-agent:stable";
    imageFile = hermesImage;
    pull = "never";
    autoStart = true;
    cmd = [ "gateway" "run" ];
    # Host networking so the guest nftables firewall is what gates 8642/9119
    # (podman-published ports bypass it). Both bind 0.0.0.0 inside the guest.
    extraOptions = [ "--network=host" "--shm-size=2g" ];
    volumes = [
      "/var/lib/hermes:/opt/data"
      "${config.sops.templates."hermes-managed-config".path}:/etc/hermes/config.yaml:ro"
    ];
    environment = {
      HERMES_DASHBOARD = "1";
      API_SERVER_ENABLED = "true";
      API_SERVER_HOST = "0.0.0.0";
      MATRIX_HOMESERVER = "https://matrix.rueb.dev";
      MATRIX_ALLOWED_USERS = "@r3v2:matrix.rueb.dev,@moni:matrix.rueb.dev";
      MATRIX_ALLOWED_ROOMS = matrixRoom;
      MATRIX_REQUIRE_MENTION = "true";
      MATRIX_E2EE_MODE = "required";
    };
    environmentFiles = [ config.sops.templates."hermes.env".path ];
  };

  systemd.services.podman-hermes = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "sops-install-secrets.service" ];
    serviceConfig.RestartSec = "10s";
  };
}
