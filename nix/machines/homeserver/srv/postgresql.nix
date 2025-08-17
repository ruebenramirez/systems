{ config, pkgs, pkgs-unstable, ... }:

{

  # PostgreSQL database with custom data location
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/tank/var/lib/postgresql";
  };

  # Create required directories and set permissions
  systemd.tmpfiles.rules = [
    # Main directory structure
    "d /tank/var 0755 root root -"
    "d /tank/var/lib 0755 root root -"
    "d /tank/var/lib/postgresql 0750 postgres postgres -"
  ];

  # Automatic db backups
  services.postgresqlBackup = {
    enable = true;
    location = "/tank/backups/homeserver/postgresql";
  };

  # Create required directories and set permissions
  # systemd.tmpfiles.rules = [
  #   # Main directory structure
  #   "d /tank/backups/homeserver/postgresql 0750 postgres postgres -"
  # ];

}
