{
  config,
  pkgs,
  lib,
  ...
}:

let
  domain = "code.rueb.dev";

  # Carried over from the compose deployment it replaces: 8.7 GB of repositories
  # and the sqlite DB live here. `/tank/srv/<fqdn>--<service>` is the homeserver
  # convention (see stalwart.nix). Bringing it up here is a one-time manual
  # cutover: `docker compose down` in that directory, then chown the trees to the
  # ids below.
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

  # Written over app.ini by the image's `environment-to-ini` at every start.
  # Sections with a dot or a dash cannot be spelled as an environment variable,
  # so `[cron.*]`, `[repository.pull-request]` and `[repository.signing]` stay
  # in app.ini, along with everything in the note below.
  settings = {
    server = {
      DOMAIN = domain;
      ROOT_URL = "https://${domain}/";
      HTTP_PORT = 3000;
      # The compose stack published 222->22, but app.ini advertised port 22 --
      # which is the host sshd -- so git-over-ssh never worked and no key is
      # registered in the instance. Re-enabling it needs a port above 1023, since
      # rootless podman cannot bind a privileged one.
      DISABLE_SSH = true;
      LFS_START_SERVER = true;
      LFS_MAX_FILE_SIZE = 0;
      OFFLINE_MODE = true;
    };

    repository.ROOT = "/data/git/repositories";

    security = {
      INSTALL_LOCK = true;
      REVERSE_PROXY_LIMIT = 1;
      REVERSE_PROXY_TRUSTED_PROXIES = "*";
    };

    service = {
      DISABLE_REGISTRATION = true;
      REQUIRE_SIGNIN_VIEW = false;
      REGISTER_EMAIL_CONFIRM = true;
      ENABLE_NOTIFY_MAIL = true;
      DEFAULT_ENABLE_TIMETRACKING = false;
      NO_REPLY_ADDRESS = "noreply.localhost";
    };

    # The password stays in app.ini: it is not in sops yet. Same for the
    # install-generated SECRET_KEY, INTERNAL_TOKEN, LFS_JWT_SECRET and
    # OAUTH2.JWT_SECRET -- none of them may change once issued, so they need a
    # `forgejo-server-homeserver.yaml` before they can move here.
    mailer = {
      ENABLED = true;
      SMTP_ADDR = "mail.rueb.dev";
      SMTP_PORT = 587;
      FROM = "noreply@rueb.dev";
      USER = "noreply@rueb.dev";
    };

    webhook.ALLOWED_HOST_LIST = "external,100.64.0.0/10,192.168.8.0/24";

    openid = {
      ENABLE_OPENID_SIGNIN = false;
      ENABLE_OPENID_SIGNUP = false;
    };
  };

  # `toString true` is "1", which forgejo does not read as a boolean.
  renderValue = value: if lib.isBool value then lib.boolToString value else toString value;

  environment = lib.listToAttrs (
    lib.concatMap (
      section:
      lib.mapAttrsToList (
        key: value:
        lib.nameValuePair "GITEA__${lib.toUpper section}__${lib.toUpper key}" (renderValue value)
      ) settings.${section}
    ) (lib.attrNames settings)
  );
in
{
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
      inherit environment;
      # nginx terminates TLS and proxies here; nothing else may reach gitea.
      ports = [ "127.0.0.1:3000:3000" ];
      volumes = [
        "${dataDir}:/data"
        "/etc/localtime:/etc/localtime:ro"
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
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
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
