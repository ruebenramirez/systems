{ config, pkgs, pkgs-unstable, ... }:

{

  # Redis with custom working directory
  services.redis.servers.nextcloud = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
    settings = {
      dir = pkgs.lib.mkForce "/tank/var/lib/redis";
      # Disable RDB snapshots for caching-only use (prevents MISCONF errors)
      save = pkgs.lib.mkForce "";
      stop-writes-on-bgsave-error = pkgs.lib.mkForce "no";
    };
  };

}
