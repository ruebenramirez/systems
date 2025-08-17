{ config, pkgs, pkgs-unstable, ... }:

{

  # Redis with custom working directory
  services.redis.servers.shared = {
    enable = true;
    port = 6379;
    bind = "127.0.0.1";
    settings = {
      dir = pkgs.lib.mkForce "/tank/var/lib/redis";
      maxmemory = "2gb";
      maxmemory-policy = "allkeys-lru";
      # Disable RDB snapshots for caching-only use (prevents MISCONF errors)
      save = pkgs.lib.mkForce "";
      stop-writes-on-bgsave-error = pkgs.lib.mkForce "no";
    };
  };

  # Create required directories and set permissions
  systemd.tmpfiles.rules = [
    # Main directory structure
    "d /tank/var 0755 root root -"
    "d /tank/var/lib 0755 root root -"
    "d /tank/var/lib/redis 0750 redis redis -"
  ];

}
