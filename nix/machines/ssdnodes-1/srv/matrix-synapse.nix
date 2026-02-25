{ config, pkgs, lib, ... }:

let
  matrixDomain = "matrix.rueb.dev";
  serverName = "matrix.rueb.dev";
in
{
  services.matrix-synapse = {
    enable = true;

    settings = {
      server_name = serverName;
      public_baseurl = "https://${matrixDomain}/";

      listeners = [
        {
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true;
          resources = [
            {
              names = [ "client" "federation" ];
              compress = true;
            }
          ];
        }
      ];

      database = {
        name = "psycopg2";
        args = {
          user = "matrix-synapse";
          database = "matrix-synapse";
          host = "/run/postgresql";
        };
      };

      media_store_path = "/persist/var/lib/matrix-synapse/media_store";

      url_preview_enabled = true;
      url_preview_ip_range_blacklist = [
        "127.0.0.0/8"
        "10.0.0.0/8"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "100.64.0.0/10"
        "192.0.0.0/24"
        "169.254.0.0/16"
        "::1/128"
        "fe80::/10"
        "fc00::/7"
      ];

      enable_registration = false;
      enable_registration_without_verification = false;

      allow_public_rooms_over_federation = true;

      trusted_key_servers = [
        { server_name = "matrix.org"; }
      ];
    };

    extraConfigFiles = [
      "/persist/secrets/matrix-synapse/secrets.yaml"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /persist/var/lib/matrix-synapse 0700 matrix-synapse matrix-synapse -"
    "d /persist/var/lib/matrix-synapse/media_store 0700 matrix-synapse matrix-synapse -"
    "d /persist/secrets/matrix-synapse 0700 matrix-synapse matrix-synapse -"
  ];

  systemd.services.matrix-synapse = {
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];

    preStart = lib.mkAfter ''
      # Generate signing key if it doesn't exist
      if [ ! -f /persist/var/lib/matrix-synapse/homeserver.signing.key ]; then
        ${pkgs.matrix-synapse}/bin/generate_signing_key -o /persist/var/lib/matrix-synapse/homeserver.signing.key
        chown matrix-synapse:matrix-synapse /persist/var/lib/matrix-synapse/homeserver.signing.key
      fi

      # Create secrets.yaml if it doesn't exist
      if [ ! -f /persist/secrets/matrix-synapse/secrets.yaml ]; then
        cat > /persist/secrets/matrix-synapse/secrets.yaml <<EOF
signing_key_path: /persist/var/lib/matrix-synapse/homeserver.signing.key
registration_shared_secret: $(${pkgs.openssl}/bin/openssl rand -hex 32)
macaroon_secret_key: $(${pkgs.openssl}/bin/openssl rand -hex 32)
form_secret: $(${pkgs.openssl}/bin/openssl rand -hex 32)
EOF
        chown matrix-synapse:matrix-synapse /persist/secrets/matrix-synapse/secrets.yaml
        chmod 600 /persist/secrets/matrix-synapse/secrets.yaml
      fi
    '';
  };
}
