{
  config,
  pkgs,
  lib,
  secretFile,
  ...
}:

let
  domain = "code.rueb.dev";

  # Carried over from the compose deployment it replaced: 8.7 GB of repositories
  # and the sqlite DB live here. `/tank/srv/<fqdn>--<service>` is the homeserver
  # convention (see stalwart.nix).
  dataDir = "/tank/srv/${domain}--forgejo/forgejo";

  uid = 960;
  gid = 960;

  # Rootless podman maps container uid 1 to the first subuid, and the image runs
  # gitea as its in-container `git` user (uid 1000), so every repository and
  # attachment lands on `subuidStart + 999` on the host. The group id works out
  # the same because both ranges start at `subuidStart`.
  subuidStart = 300000;
  dataUid = subuidStart + 999;

  forgejoImage = pkgs.dockerTools.pullImage {
    imageName = "codeberg.org/forgejo/forgejo";
    imageDigest = "sha256:fcd19ff4ebc85fb098a67e8e1d0d5a84d07dd6e8a23edcfdfd5b71a6178953be";
    hash = "sha256-CXkioeBWOmg99purINt5qocTiRBVnJPINg2VNSbzSXY=";
    finalImageName = "codeberg.org/forgejo/forgejo";
    finalImageTag = "17";
    os = "linux";
    arch = "amd64";
  };

  # The whole of app.ini, rendered by sops into /run and bind-mounted read-only.
  # Nothing here may change lightly: INTERNAL_TOKEN, LFS_JWT_SECRET and
  # OAUTH2.JWT_SECRET are already issued, PASSWORD_HASH_ALGO guards every stored
  # password, and SECRET_KEY is empty on purpose -- forgejo derives it, and
  # putting a value in would invalidate whatever the derived one has encrypted.
  appIni = ''
    APP_NAME = Forgejo
    RUN_MODE = prod
    APP_SLOGAN = Beyond coding. We Forge.
    RUN_USER = git
    WORK_PATH = /data/gitea

    [repository]
    ROOT = /data/git/repositories

    [repository.local]
    LOCAL_COPY_PATH = /data/gitea/tmp/local-repo

    [repository.upload]
    TEMP_PATH = /data/gitea/uploads

    [server]
    APP_DATA_PATH = /data/gitea
    DOMAIN = ${domain}
    HTTP_PORT = 3000
    ROOT_URL = https://${domain}/
    # The compose stack published 222->22 while app.ini advertised port 22, which
    # is the host sshd, so git-over-ssh never worked and no key was registered.
    # Rootless podman cannot bind a privileged port to fix it, so it stays off.
    DISABLE_SSH = true
    LFS_START_SERVER = true
    LFS_JWT_SECRET = ${config.sops.placeholder.forgejo-lfs-jwt-secret}
    LFS_MAX_FILE_SIZE = 0
    OFFLINE_MODE = true

    [database]
    PATH = /data/gitea/gitea.db
    DB_TYPE = sqlite3
    LOG_SQL = false
    SSL_MODE = disable

    [indexer]
    ISSUE_INDEXER_PATH = /data/gitea/indexers/issues.bleve

    [session]
    PROVIDER_CONFIG = /data/gitea/sessions
    PROVIDER = file

    [picture]
    AVATAR_UPLOAD_PATH = /data/gitea/avatars
    REPOSITORY_AVATAR_UPLOAD_PATH = /data/gitea/repo-avatars

    [attachment]
    PATH = /data/gitea/attachments

    [log]
    MODE = file
    LEVEL = info
    ROOT_PATH = /data/gitea/log

    [security]
    INSTALL_LOCK = true
    SECRET_KEY =
    REVERSE_PROXY_LIMIT = 1
    REVERSE_PROXY_TRUSTED_PROXIES = *
    INTERNAL_TOKEN = ${config.sops.placeholder.forgejo-internal-token}
    PASSWORD_HASH_ALGO = pbkdf2_hi

    [service]
    DISABLE_REGISTRATION = true
    REQUIRE_SIGNIN_VIEW = false
    REGISTER_EMAIL_CONFIRM = true
    ENABLE_NOTIFY_MAIL = true
    ALLOW_ONLY_EXTERNAL_REGISTRATION = false
    ENABLE_CAPTCHA = false
    DEFAULT_KEEP_EMAIL_PRIVATE = false
    DEFAULT_ALLOW_CREATE_ORGANIZATION = true
    DEFAULT_ENABLE_TIMETRACKING = false
    NO_REPLY_ADDRESS = noreply.localhost

    [lfs]
    PATH = /data/git/lfs

    [mailer]
    ENABLED = true
    SMTP_ADDR = mail.rueb.dev
    SMTP_PORT = 587
    FROM = noreply@rueb.dev
    USER = noreply@rueb.dev
    PASSWD = ${config.sops.placeholder.forgejo-smtp-password}

    [openid]
    ENABLE_OPENID_SIGNIN = false
    ENABLE_OPENID_SIGNUP = false

    [cron.update_checker]
    ENABLED = true

    [cron.repo_health_check]
    SCHEDULE = @midnight
    TIMEOUT = 300s

    [repository.pull-request]
    DEFAULT_MERGE_STYLE = merge

    [repository.signing]
    DEFAULT_TRUST_MODEL = committer

    [oauth2]
    JWT_SECRET = ${config.sops.placeholder.forgejo-oauth2-jwt-secret}

    [webhook]
    ALLOWED_HOST_LIST = external,100.64.0.0/10,192.168.8.0/24
  '';
in
{
  sops.secrets = {
    forgejo-internal-token = secretFile "forgejo-server-homeserver";
    forgejo-lfs-jwt-secret = secretFile "forgejo-server-homeserver";
    forgejo-oauth2-jwt-secret = secretFile "forgejo-server-homeserver";
    forgejo-smtp-password = secretFile "forgejo-server-homeserver";
  };

  # Owned by the container's git uid: the sops directory is world-traversable and
  # 0400 keeps the plaintext off every other reader on the host.
  sops.templates."forgejo-app.ini" = {
    content = appIni;
    uid = dataUid;
    gid = dataUid;
    mode = "0400";
    restartUnits = [ "podman-forgejo.service" ];
  };

  users.groups.forgejo.gid = gid;
  users.users.forgejo = {
    inherit uid;
    isSystemUser = true;
    group = "forgejo";
    home = "/var/lib/forgejo";
    shell = "${pkgs.shadow}/bin/nologin";
    # Rootless containers are systemd user services, so the user manager has to
    # exist without a login session.
    linger = true;
    subUidRanges = [
      {
        startUid = subuidStart;
        count = 65536;
      }
    ];
    subGidRanges = [
      {
        startGid = subuidStart;
        count = 65536;
      }
    ];
  };

  systemd.tmpfiles.rules = [
    # podman's image store for this user
    "d /var/lib/forgejo          0700 ${toString uid} ${toString gid} -"
    # Only the top levels: the trees below them are chowned once, by hand. The
    # data group owns `${dataDir}` itself because both the container's root (uid
    # `uid`) and its `git` user (uid `dataUid`) have to traverse it.
    "d ${dataDir}        0750 ${toString uid} ${toString dataUid} -"
    "d ${dataDir}/ssh    0700 ${toString uid} ${toString gid} -"
    "d ${dataDir}/gitea  0750 ${toString dataUid} ${toString dataUid} -"
    "d ${dataDir}/git    0750 ${toString dataUid} ${toString dataUid} -"
  ];

  virtualisation.oci-containers = {
    backend = "podman";

    containers.forgejo = {
      image = "codeberg.org/forgejo/forgejo:17";
      imageFile = forgejoImage;
      pull = "never";
      autoStart = true;
      podman.user = "forgejo";
      # nginx terminates TLS and proxies here; nothing else may reach gitea.
      ports = [ "127.0.0.1:3000:3000" ];
      volumes = [
        "${dataDir}:/data"
        "/etc/localtime:/etc/localtime:ro"
        # Last so it wins over the /data mount on the subpath. The image's own
        # `environment-to-ini` would rewrite this file if any GITEA__ variable
        # were set, so none are: app.ini is the only config input now.
        #
        # The stale copy this shadows is kept on purpose: with nothing at that
        # path podman creates a 0-byte app.ini as the mount target, and an
        # app.ini without INSTALL_LOCK offers the installer against a populated
        # database instead of failing.
        "${config.sops.templates."forgejo-app.ini".path}:/data/gitea/conf/app.ini:ro"
      ];
      extraOptions = [
        "--health-cmd=curl -fsS http://127.0.0.1:3000/api/healthz"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=3"
        "--health-start-period=30s"
        "--health-on-failure=kill"
      ];
    };
  };

  systemd.services.podman-forgejo = {
    # Rootless podman drives cgroups and healthchecks through the user manager;
    # without it crun dies on `sd-bus call: Access denied`. `oci-containers` only
    # orders user@ for sdnotify=healthy and this unit uses conmon.
    requires = [ "user@${toString uid}.service" ];
    after = [
      "network-online.target"
      "user@${toString uid}.service"
      # Ordering only: the unit is `bad-setting` and never runs as a job, the
      # activation script installs secrets directly. See docs/secrets.md.
      "sops-install-secrets.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig.RestartSec = "10s";
  };

  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.nginx = {
    enable = true;

    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts.${domain} = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = "client_max_body_size 400m;";
      };
    };
  };
}
