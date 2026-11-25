{ config, lib, pkgs, tailnet, secretFile, pullImageWithRetry, ... }:

let
  # `nousresearch/hermes-agent:stable`, digest-pinned (amd64 manifest). Verified
  # 2026-10-09: Python 3.14.7, `import olm` OK (no pre-3.14 fallback needed),
  # runs as uid/gid 10000, state under HERMES_HOME=/opt/data.
  hermesImage = pullImageWithRetry {
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
  matrixRoom = "!i7gn4E-fEgrxo85VEe90EHbiZusAThDm6FSAfV2w-Ls";

  # Managed scope (`/etc/hermes`), deep-merged over the user config and wins.
  # The dashboard refuses to bind 0.0.0.0 unless `dashboard.basic_auth` is
  # configured here (env vars alone do not register the auth provider).
  managedConfig = ''
    dashboard:
      basic_auth:
        username: ${config.sops.placeholder.hermes-dashboard-basic-auth-username}
        password: ${config.sops.placeholder.hermes-dashboard-basic-auth-password}
        secret: ${config.sops.placeholder.hermes-dashboard-basic-auth-secret}
    # No model.default pin here: managed scope wins over EVERY profile's
    # config.yaml, so a pin forces one model fleet-wide. Per-profile defaults
    # live in user scope (default profile: halogen; Henry: deepseek).
    # providers.halogen + base_url stay so the two cannot disagree about
    # where inference goes.
    providers:
      halogen:
        base_url: http://${tailnet.host "fwai0"}:8731/v1
        key_env: HALOGEN_API_KEY
        api_mode: chat_completions
        models:
          halogen-qwen3.8-flash-next: {}
  '';

  # The flake is the source of truth for the `model:` scope below: the `C`
  # tmpfiles rules seed a config only when it is absent, so a value changed in
  # the flake never reaches a live profile -- and a profile with no
  # model.default does not fail, it quietly runs the provider's first catalog
  # model (rueb/systems#126: after #119 dropped the managed pin, Henry answered
  # in z-ai/glm-5.3). Apply the capture's whole `model:` block (default,
  # provider, aliases, api_mode) before the gateway starts; the values are read
  # back out of the capture file, so the flake stays the only place the model
  # scope is edited.
  #
  # Consequence: the flake wins over the dashboard and over live edits. A model
  # or alias set anywhere else holds only until the next activation; declare it
  # in the capture to make it stick.
  modelPins = [
    {
      label = "default profile";
      seed = ./hermes-config.yaml;
      live = "/var/lib/hermes/config.yaml";
    }
    {
      label = "henry profile";
      seed = ./profiles/henry/config.yaml;
      live = "/var/lib/hermes/profiles/henry/config.yaml";
    }
  ];

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
  imports = [ ../../_common/container-mirrors.nix ];

  my.containerMirrors.enable = true;

  sops.secrets = {
    hermes-dashboard-basic-auth-username =
      secretFile "hermes-agent-server-hermes-vm-xps";
    hermes-dashboard-basic-auth-password =
      secretFile "hermes-agent-server-hermes-vm-xps";
    hermes-dashboard-basic-auth-secret =
      secretFile "hermes-agent-server-hermes-vm-xps";
    hermes-api-server-key = secretFile "hermes-agent-server-hermes-vm-xps";
    # Hermes runs its own inference endpoint (halogen) and has its own
    # OpenRouter credential, so it must not read the shared personal key.
    openrouter-api-key = secretFile "openrouter-client-hermes-vm-xps";
    matrix-access-token = secretFile "matrix-client-hermes-vm-xps";
    matrix-recovery-key = secretFile "matrix-client-hermes-vm-xps";
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
    # Seed the user config on a fresh state dir only (C = never overwrite an
    # existing file): a from-scratch rebuild is recovered from these captures.
    # On an existing state dir the flake is applied instead -- the model scope
    # by hermes-model-pin at every activation, the rest reported as drift by
    # scripts/check-hermes-config-drift.py so a live-only key gets declared here
    # deliberately. Do not edit live config to match the flake.
    "C /var/lib/hermes/config.yaml ${./hermes-config.yaml} 0600 10000 10000 -"
    # Profile seeds (same C semantics): recovery source for a fresh state dir,
    # plus the model scope applied at activation.
    "d /var/lib/hermes/profiles/henry 0700 10000 10000 -"
    "C /var/lib/hermes/profiles/henry/config.yaml ${./profiles/henry/config.yaml} 0600 10000 10000 -"
    "C /var/lib/hermes/profiles/henry/profile.yaml ${./profiles/henry/profile.yaml} 0600 10000 10000 -"
  ];

  virtualisation.oci-containers.backend = "podman";
  virtualisation.oci-containers.containers.hermes = {
    image = "nousresearch/hermes-agent:stable";
    imageFile = hermesImage;
    pull = "never";
    autoStart = true;
    cmd = [ "gateway" "run" ];
    # Host networking; ports bind 0.0.0.0, access gated by firewall + headscale ACLs.
    extraOptions = [ "--network=host" "--shm-size=2g" ];
    volumes = [
      "/var/lib/hermes:/opt/data"
      "${config.sops.templates."hermes-managed-config".path}:/etc/hermes/config.yaml:ro"
      # ~/.ssh must live on the persistent dir or the overlay wipes it each
      # rebuild; must follow the /opt/data mount to win on the subpath.
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
    wants = [
      "network-online.target"
      "hermes-profile-env-sync.service"
      "hermes-model-pin.service"
    ];
    after = [
      "network-online.target"
      "sops-install-secrets.service"
      "hermes-profile-env-sync.service"
      "hermes-model-pin.service"
    ];
    # A profile that starts un-pinned runs whatever the provider catalog
    # happens to lead with, so a pin that cannot be written stops the gateway
    # rather than silently spending on the wrong model.
    requires = [ "hermes-profile-env-sync.service" "hermes-model-pin.service" ];
    serviceConfig.RestartSec = "10s";
  };

  # Runs as root: the live configs are 0600 under /var/lib/hermes and Hermes
  # itself is uid 10000, so the writer restores owner and mode on every file it
  # touches. Ordered after tmpfiles so a first-boot state dir is already seeded.
  systemd.services.hermes-model-pin = {
    description = "Apply the flake's Hermes model scope to existing profile scopes";
    after = [ "systemd-tmpfiles-setup.service" "sops-install-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      ${lib.concatMapStrings (pin: ''
        ${pkgs.python3}/bin/python3 ${../../../../scripts/hermes-apply-model-pin.py} \
          --seed ${pin.seed} --live ${pin.live} --label ${lib.escapeShellArg pin.label}
      '') modelPins}
    '';
  };

  # Hermes reads platform credentials from the profile scope (~/.hermes/.env)
  # and will not fall back to os.environ, so container env vars are invisible to
  # it. Upsert the Matrix values Nix owns into that scope before start; the
  # access token is read from the sops env file at runtime so it never lands in
  # the store.
  systemd.services.hermes-profile-env-sync =
    let
      plain = {
        MATRIX_HOMESERVER = "https://matrix.rueb.dev";
        MATRIX_ALLOWED_USERS = "@r3v2:matrix.rueb.dev,@moni:matrix.rueb.dev";
        MATRIX_ALLOWED_ROOMS = matrixRoom;
        MATRIX_REQUIRE_MENTION = "true";
        MATRIX_E2EE_MODE = "required";
        # Email platform (Stalwart). Non-secret routing only; EMAIL_PASSWORD
        # stays in the live profile .env until it moves to sops.
        EMAIL_ADDRESS = "hermes@rueb.dev";
        EMAIL_IMAP_HOST = "mail.rueb.dev";
        EMAIL_IMAP_PORT = "993";
        EMAIL_SMTP_HOST = "mail.rueb.dev";
        EMAIL_SMTP_PORT = "587";
        EMAIL_POLL_INTERVAL = "15";
        EMAIL_ALLOWED_USERS = "r3v2@rueb.dev,monica@monicarosephotography.com";
        EMAIL_HOME_ADDRESS = "r3v2@rueb.dev";
        EMAIL_TRUST_FROM_HEADER = "true";
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
