{ config, lib, pkgs, tailnet, ... }:

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
    # Default the agent at the local halogen engine on fwai0 instead of
    # OpenRouter. `providers.<name>` with a base_url is a custom-endpoint
    # definition (hermes_cli/providers.py:resolve_user_provider), and the
    # provider is selected by that key name. `model.base_url` is set as well so
    # the two cannot disagree about where inference goes.
    model:
      default: halogen-qwen3.8-flash-next
      provider: halogen
      base_url: http://${tailnet.host "fwai0"}:8731/v1
    providers:
      halogen:
        base_url: http://${tailnet.host "fwai0"}:8731/v1
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
    # SSH keypair the agent uses to reach this VM. Created here so the directory
    # survives even if the state dir is re-staged; the private key itself is
    # generated once by hand (never committed, never in the Nix store).
    "d /var/lib/hermes/.ssh 0700 10000 10000 -"
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
      # The container's HOME is /root, so `~/.ssh` would land in the overlay and
      # be destroyed on every rebuild. Bind-mounting the persistent state dir
      # over it means the agent's plain `ssh`/`scp` keep working while the key
      # actually lives under /opt/data/.ssh (host: /var/lib/hermes/.ssh).
      # Must come after the /opt/data mount so it wins on the subpath.
      "/var/lib/hermes/.ssh:/root/.ssh"
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
    wants = [ "network-online.target" "hermes-profile-env-sync.service" ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
      "hermes-profile-env-sync.service"
    ];
    requires = [ "hermes-profile-env-sync.service" ];
    serviceConfig.RestartSec = "10s";
  };

  # Hermes resolves platform credentials from the *profile* secret scope
  # (~/.hermes/.env) and deliberately refuses to fall back to os.environ once a
  # scope exists. Anything placed only in the container environment is invisible
  # to the adapter: the Matrix bridge sat "enabled but unserved" this way, and
  # with an empty allowlist it rejected every invite, including from users who
  # were on the list.
  #
  # Upsert the Matrix values Nix owns into that scope before the container
  # starts. The access token is read from the sops-rendered env file at runtime
  # so it never lands in the Nix store; every other key in the file is left
  # untouched.
  systemd.services.hermes-profile-env-sync =
    let
      plain = {
        MATRIX_HOMESERVER = "https://matrix.rueb.dev";
        MATRIX_ALLOWED_USERS = "@r3v2:matrix.rueb.dev,@moni:matrix.rueb.dev";
        MATRIX_ALLOWED_ROOMS = matrixRoom;
        MATRIX_REQUIRE_MENTION = "true";
        MATRIX_E2EE_MODE = "required";
      };
      upsert = key: value: ''
        if grep -q "^${key}=" "$envf" 2>/dev/null; then
          sed -i "s|^${key}=.*|${key}=${value}|" "$envf"
        else
          printf '%s=%s\n' "${key}" "${value}" >> "$envf"
        fi
      '';
      # Secrets that live in the sops-rendered env file and must be copied into
      # the profile scope by name, never baked into the store.
      secretKeys = [
        "MATRIX_ACCESS_TOKEN"
        "OPENROUTER_API_KEY"
        "HALOGEN_API_KEY"
      ];
      copySecret = key: ''
        val="$(grep -m1 '^${key}=' "$src" | cut -d= -f2- || true)"
        if [ -n "$val" ]; then
          if grep -q "^${key}=" "$envf" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=$val|" "$envf"
          else
            printf '%s=%s\n' "${key}" "$val" >> "$envf"
          fi
        else
          echo "warning: ${key} not present in the rendered env file; leaving profile scope untouched" >&2
        fi
      '';
    in
    {
      description = "Sync Nix-owned Matrix values into the Hermes profile secret scope";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.gnused pkgs.gnugrep pkgs.coreutils ];
      script = ''
        envf=/var/lib/hermes/.env
        src=${config.sops.templates."hermes.env".path}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList upsert plain)}
        ${lib.concatStringsSep "\n" (map copySecret secretKeys)}
        chown 10000:10000 "$envf"
        chmod 600 "$envf"
      '';
    };
}
