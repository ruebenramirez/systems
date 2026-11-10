{
  config,
  pkgs,
  lib,
  secretFile,
  ...
}:

let
  inherit (lib)
    flatten
    mapAttrs'
    mapAttrsToList
    nameValuePair
    ;

  # Rootless podman, one user for all four containers so the pinned images are
  # stored once rather than four times.
  uid = 965;
  gid = 965;
  subuidStart = 400000;

  # Rootless uid mapping is off by one from the obvious guess: container uid 0 is
  # `wordpress` itself, and only uid 1 and up land in the subuid range -- so a
  # container uid N > 0 is `subuidStart + N - 1` on the host. Verified by creating
  # a file as container root (host 965) and reading the datadir's own ownership
  # back (mariadb chowns its datadir to uid 999, which shows up as 400998).
  containerRootUid = uid;

  # mariadb's `mysql` is container uid 999 -> host 400998. Chowning the datadir to
  # 400999 instead does not fail: the entrypoint just chowns it again at startup,
  # which is how this was caught.
  mysqlHostUid = subuidStart + 999 - 1;

  # One entry per site. The data trees keep the paths the compose-era scripts
  # used: srv/hosted-sites-backup-source.nix lets homeserver rsync `/srv`
  # read-only, so moving them would silently drop the backups.
  sites = {
    monicaandrueben = {
      domain = "monicaandrueben.com";
      port = 8012;
    };
    monicarosephotography = {
      domain = "monicarosephotography.com";
      port = 8011;
    };
  };

  # Pinned to the digests the running docker containers were built from, resolved
  # by matching each container's image ID to the amd64 manifest config.
  #
  # This wordpress digest is an upstream `latest` carrying WP 7.1.3, which neither
  # site runs: WordPress core lives in the html bind mount and the entrypoint only
  # seeds it when absent. What the pin buys is PHP 8.3.36 and Apache, unchanged.
  wordpressImage = pkgs.dockerTools.pullImage {
    imageName = "docker.io/library/wordpress";
    imageDigest = "sha256:d42f63cb89ad0eab272c4b393164e63830d0df270009907919f7dcce52b1a20b";
    hash = "sha256-zKAtb08FAWNNvdV7f/6rfxB/f4Yc1eDxrASVE6n+rjo=";
    finalImageName = "docker.io/library/wordpress";
    finalImageTag = "latest";
    os = "linux";
    arch = "amd64";
  };

  # 13.0.2 deliberately. The datadir marker says 11.6.2 and the image skips
  # `mariadb-upgrade` unless told otherwise, so an 11.6-era datadir is being served
  # by 13.0.2 today. Pinning holds that exactly; finishing the schema upgrade is a
  # separate change with a dump in front of it.
  mariadbImage = pkgs.dockerTools.pullImage {
    imageName = "docker.io/library/mariadb";
    imageDigest = "sha256:0e4bb0f339feba125d1154fbacd36c16ec8518f52e44e1f82ecec7d6771caf39";
    hash = "sha256-q4EmAHMwcPiwQxlEslHFJ76LthvpJ07IV23cVMdb/+U=";
    finalImageName = "docker.io/library/mariadb";
    finalImageTag = "13.0.2";
    os = "linux";
    arch = "amd64";
  };

  uploadsIni = pkgs.writeText "wordpress-uploads.ini" ''
    file_uploads = On
    memory_limit = 64M
    upload_max_filesize = 64M
    post_max_size = 64M
    max_execution_time = 600
  '';

  secretKeys = [
    "db-root-password"
    "db-password"
    "auth-key"
    "secure-auth-key"
    "logged-in-key"
    "nonce-key"
    "auth-salt"
    "secure-auth-salt"
    "logged-in-salt"
    "nonce-salt"
  ];

  # mariadb reads MYSQL_* and the wordpress entrypoint reads WORDPRESS_*.
  #
  # The salts are read only when an install has to seed a wp-config.php; both sites
  # already have one, and its values are the ones in use -- which are NOT the ones
  # the retired deploy scripts passed. They are here so a rebuilt html/ reproduces
  # the current site instead of minting new keys and logging everyone out.
  envFile = name: ''
    MYSQL_DATABASE=wordpress_db
    MYSQL_USER=wpuser
    MYSQL_PASSWORD=${config.sops.placeholder."${name}-db-password"}
    MYSQL_ROOT_PASSWORD=${config.sops.placeholder."${name}-db-root-password"}
    WORDPRESS_DB_HOST=mysql
    WORDPRESS_DB_USER=wpuser
    WORDPRESS_DB_NAME=wordpress_db
    WORDPRESS_DB_PASSWORD=${config.sops.placeholder."${name}-db-password"}
    WORDPRESS_AUTH_KEY=${config.sops.placeholder."${name}-auth-key"}
    WORDPRESS_SECURE_AUTH_KEY=${config.sops.placeholder."${name}-secure-auth-key"}
    WORDPRESS_LOGGED_IN_KEY=${config.sops.placeholder."${name}-logged-in-key"}
    WORDPRESS_NONCE_KEY=${config.sops.placeholder."${name}-nonce-key"}
    WORDPRESS_AUTH_SALT=${config.sops.placeholder."${name}-auth-salt"}
    WORDPRESS_SECURE_AUTH_SALT=${config.sops.placeholder."${name}-secure-auth-salt"}
    WORDPRESS_LOGGED_IN_SALT=${config.sops.placeholder."${name}-logged-in-salt"}
    WORDPRESS_NONCE_SALT=${config.sops.placeholder."${name}-nonce-salt"}
  '';
in
{
  imports = [ ../../_common/container-mirrors.nix ];

  my.containerMirrors.enable = true;

  virtualisation.podman.enable = true;

  users.groups.wordpress.gid = gid;
  users.users.wordpress = {
    inherit uid;
    isSystemUser = true;
    group = "wordpress";
    home = "/var/lib/wordpress";
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

  # Per-site network so the db answers to `mysql`, which is what both wp-config.php
  # files use -- one via getenv_docker's default, one as a literal. Neither
  # container publishes 3306, so a database is reachable only from its own site.
  #
  # Rootless networks belong to the user, so this runs as the user. Container
  # units are system units with User=wordpress, so they can be ordered directly.
  systemd.services = lib.mkMerge [
    (builtins.listToAttrs (
      mapAttrsToList (name: site: {
        name = "podman-network-${name}";
        value = {
          description = "Podman network for ${site.domain}";
          wantedBy = [ "multi-user.target" ];
          before = [
            "podman-${name}-db.service"
            "podman-${name}-wp.service"
          ];
          after = [ "user@${toString uid}.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "wordpress";
            Group = "wordpress";
          };
          environment = {
            XDG_RUNTIME_DIR = "/run/user/${toString uid}";
          };
          script = ''
            ${pkgs.podman}/bin/podman network exists wordpress-${name} || \
              ${pkgs.podman}/bin/podman network create wordpress-${name}
          '';
        };
      }) sites
    ))

    # Rootless podman reaches cgroups and healthchecks through the user manager;
    # without it crun fails on `sd-bus call: Access denied`. oci-containers orders
    # user@ only for sdnotify=healthy and these units use conmon.
    # `after` on sops-install-secrets is ordering only -- that unit is `bad-setting`
    # and never runs as a job.
    (builtins.listToAttrs (
      mapAttrsToList (name: site: {
        name = "podman-${name}-db";
        value = {
          requires = [ "user@${toString uid}.service" ];
          after = [
            "user@${toString uid}.service"
            "sops-install-secrets.service"
          ];
        };
      }) sites
    ))
    (builtins.listToAttrs (
      mapAttrsToList (name: site: {
        name = "podman-${name}-wp";
        value = {
          requires = [ "user@${toString uid}.service" ];
          after = [
            "user@${toString uid}.service"
            "sops-install-secrets.service"
          ];
        };
      }) sites
    ))
  ];

  # Key names carry the site because sops-nix keys are global to the host, not to
  # the file they live in.
  sops.secrets = builtins.listToAttrs (
    flatten (
      mapAttrsToList (
        name: site:
        map (k: {
          name = "${name}-${k}";
          value = secretFile "wordpress-${name}-server-ssdnodes-1";
        }) secretKeys
      ) sites
    )
  );

  sops.templates = mapAttrs' (
    name: site:
    nameValuePair "wordpress-${name}.env" {
      content = envFile name;
      # Owned by the host user that runs podman: --env-file is opened on the host
      # before any namespace exists.
      uid = uid;
      gid = gid;
      mode = "0400";
      restartUnits = [
        "podman-${name}-db.service"
        "podman-${name}-wp.service"
      ];
    }
  ) sites;

  environment.etc."wordpress/uploads.ini".source = uploadsIni;

  # Top levels only. The recursive chown to the mapped uids was done once, by hand,
  # at cutover; re-walking 15 G on every activation would buy nothing.
  systemd.tmpfiles.rules = flatten (
    mapAttrsToList (name: site: [
      # podman's image store for this user
      "d /var/lib/wordpress                              0700 ${toString uid} ${toString gid} -"
      "d /srv/${site.domain}--wordpress                  0755 ${toString uid} ${toString gid} -"
      "d /srv/${site.domain}--wordpress/html             0755 ${toString containerRootUid} ${toString containerRootUid} -"
      "d /srv/${site.domain}--wordpress/database         0755 ${toString mysqlHostUid} ${toString mysqlHostUid} -"
    ]) sites
  );

  virtualisation.oci-containers = {
    backend = "podman";

    containers = builtins.listToAttrs (
      flatten (
        mapAttrsToList (name: site: [
          {
            name = "${name}-db";
            value = {
              image = "docker.io/library/mariadb:13.0.2";
              imageFile = mariadbImage;
              pull = "never";
              autoStart = true;
              podman.user = "wordpress";
              networks = [ "wordpress-${name}" ];
              environmentFiles = [ config.sops.templates."wordpress-${name}.env".path ];
              volumes = [ "/srv/${site.domain}--wordpress/database:/var/lib/mysql" ];
              extraOptions = [
                "--network-alias"
                "mysql"
                "--health-cmd"
                # mariadb's own healthcheck.sh connects as passwordless root, which
                # only works where the datadir's root still accepts unix_socket
                # auth: it passed on one site and reported Access denied on the
                # other. MYSQL_PWD keeps the password out of argv.
                "env MYSQL_PWD=\"$MYSQL_ROOT_PASSWORD\" mariadb-admin -h 127.0.0.1 -uroot ping"
                "--health-interval=30s"
                "--health-timeout=10s"
                "--health-retries=3"
                "--health-start-period=60s"
              ];
            };
          }
          {
            name = "${name}-wp";
            value = {
              image = "docker.io/library/wordpress:latest";
              imageFile = wordpressImage;
              pull = "never";
              autoStart = true;
              podman.user = "wordpress";
              dependsOn = [ "${name}-db" ];
              networks = [ "wordpress-${name}" ];
              environmentFiles = [ config.sops.templates."wordpress-${name}.env".path ];
              # Loopback only; nginx proxies from here. The docker containers
              # published 0.0.0.0, which left both sites reachable in cleartext on
              # 8011 and 8012 beside the TLS front.
              ports = [ "127.0.0.1:${toString site.port}:80" ];
              volumes = [
                "/srv/${site.domain}--wordpress/html:/var/www/html"
                "/etc/wordpress/uploads.ini:/usr/local/etc/php/conf.d/uploads.ini:ro"
              ];
              extraOptions = [
                "--health-cmd"
                "curl -fsS http://127.0.0.1/"
                "--health-interval=30s"
                "--health-timeout=10s"
                "--health-retries=3"
                "--health-start-period=60s"
              ];
            };
          }
        ]) sites
      )
    );
  };
}
