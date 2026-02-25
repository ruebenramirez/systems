{ config, pkgs, ... }:

{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/persist/var/lib/postgresql";

    ensureDatabases = [ "matrix-synapse" ];
    ensureUsers = [
      {
        name = "matrix-synapse";
        ensureDBOwnership = true;
      }
    ];

    # Synapse requires C locale for proper text search
    settings = {
      lc_collate = "C";
      lc_ctype = "C";
    };
  };

  systemd.tmpfiles.rules = [
    "d /persist/var 0755 root root -"
    "d /persist/var/lib 0755 root root -"
    "d /persist/var/lib/postgresql 0750 postgres postgres -"
    "d /persist/backups 0755 root root -"
    "d /persist/backups/postgresql 0750 postgres postgres -"
  ];

  services.postgresqlBackup = {
    enable = true;
    location = "/persist/backups/postgresql";
    databases = [ "matrix-synapse" ];
  };
}
