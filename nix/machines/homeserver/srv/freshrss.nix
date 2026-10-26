{ config, lib, pkgs, pkgs-unstable, systems-secrets, ... }: {

  # declare sops secret for freshrss-pass
  # restartUnits is required: the unit embeds only the secret *path*, so a new
  # value changes no derivation and systemd would otherwise never re-run it,
  # leaving the old password live despite a "successful" deploy.
  sops.secrets.freshrss-pass = { restartUnits = [ "freshrss-config.service" ]; };

  # Grant Nginx access to read the certificate owned by the shared group
  users.users.nginx.extraGroups = [ "ruebdev-wildcard-tls" ];

  services.freshrss = {
    enable = true;
    baseUrl = "https://freshrss.rueb.dev";
    database.type = "sqlite";
    passwordFile = config.sops.secrets.freshrss-pass.path;
    defaultUser = "admin";
    package = pkgs-unstable.freshrss;
    virtualHost = "freshrss.rueb.dev";
    webserver = "nginx";
  };

  services.nginx = {
    enable = true;

    # Recommended default settings
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    virtualHosts."freshrss.rueb.dev" = {
      forceSSL = true;

      # Use the wildcard cert defined in acme-wildcard.nix
      useACMEHost = "rueb.dev";

      # Notice there is no proxyPass or locations block here.
      # The services.freshrss module injects the necessary PHP-FPM locations automatically.
    };
  };
}
