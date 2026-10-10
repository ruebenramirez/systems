{ pkgs, ... }:
{
  # Continuwuity Matrix homeserver, federating from https://matrix.rueb.dev.
  #
  # Ingress: HAProxy :443 (SNI) -> nginx 127.0.0.1:8444 (PROXY protocol) ->
  # continuwuity 127.0.0.1:6167. HTTP-01 on :80; DNS for matrix.rueb.dev must be
  # grey-cloud (DNS-only) so ACME and federation reach this host.
  services.matrix-continuwuity = {
    enable = true; # admin.enable defaults true -> `conduwuit` admin wrapper on PATH
    # Default `matrix-continuwuity` in 26.05 is 0.5.10 (flagged insecure: SEC8);
    # the maintainers recommend the 26.x line.
    package = pkgs.matrix-continuwuity_latest;
    settings.global = {
      server_name = "matrix.rueb.dev"; # IMMUTABLE (changing it requires a DB wipe)
      allow_federation = true;
      allow_encryption = true;
      max_request_size = 104857600; # 100 MB; keep nginx in sync
      allow_public_room_directory_over_federation = false;
      require_auth_for_profile_requests = true;
      new_user_displayname_suffix = "";
      database_backup_path = "/var/lib/continuwuity/db-backups"; # must live inside StateDirectory
      well_known = {
        client = "https://matrix.rueb.dev";
        server = "matrix.rueb.dev:443"; # 443 delegation
      };

      # Registration is closed; accounts are managed via `!admin users`.
      allow_registration = false;
    };
  };

  services.nginx.virtualHosts."matrix.rueb.dev" = {
    enableACME = true; # HTTP-01 via nginx :80 (grey-cloud DNS)
    addSSL = true;
    listen = [
      { addr = "0.0.0.0"; port = 80; }
      { addr = "[::0]"; port = 80; }
      { addr = "127.0.0.1"; port = 8444; ssl = true; proxyProtocol = true; }
      { addr = "[::1]"; port = 8444; ssl = true; proxyProtocol = true; }
    ];
    locations."/" = {
      proxyPass = "http://127.0.0.1:6167"; # module default port
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 100m;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
  };
}
