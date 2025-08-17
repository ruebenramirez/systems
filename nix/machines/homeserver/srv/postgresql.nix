{ config, pkgs, pkgs-unstable, ... }:

{

  # PostgreSQL database with custom data location
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/tank/var/lib/postgresql";
  };

}
