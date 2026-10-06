{ config, pkgs, pkgs-unstable, ... }: {

  # Cloudflare Tunnel for photos.monicaandrueben.com
  services.cloudflared = {
    enable = true;
    package = pkgs-unstable.cloudflared;
    tunnels = {
      "459c9edd-ceba-4e65-b5a0-c77b5af24939" = {
        credentialsFile = "/persist/cloudflared/459c9edd-ceba-4e65-b5a0-c77b5af24939.json";
        ingress = {
          "photos.monicaandrueben.com" = "http://127.0.0.1:3001";
        };
        default = "http_status:404";
      };
    };
  };

	services.immich = {
		enable = true;

		# Storage location
		mediaLocation = "/tank/immich/";

		# Network configuration
		port = 3001;
		host = "0.0.0.0";
		openFirewall = true;

		# Hardware acceleration
		accelerationDevices = null; # Full device access

		# Postgresql Database configuration managed by the module
		database = {
			enable = true;
			createDB = true;
		};

		# Redis configuration
    redis = {
      enable = false;
      host = "127.0.0.1";
      port = 6379;
    };
    # dedicate DB 1 for immich use
    environment.REDIS_DBINDEX = "1";

		# Machine learning with CUDA
		machine-learning.enable = true;

		# Configure via web interface
		settings = null;
	};

	# Add immich user to hardware acceleration groups
	users.users.immich.extraGroups = [ "video" "render" ];

  # Automatic db backups
  services.postgresqlBackup = {
    databases = [ "immich" ];
  };

}
