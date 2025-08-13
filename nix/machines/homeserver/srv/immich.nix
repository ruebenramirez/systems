{ config, pkgs, pkgs-unstable, ... }:

{
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

		# Database configuration
		database = {
			enable = true;
			createDB = true;
		};

		# Redis configuration
		redis.enable = true;

		# Machine learning with CUDA
		machine-learning.enable = true;

		# Configure via web interface
		settings = null;
	};

	# Add immich user to hardware acceleration groups
	users.users.immich.extraGroups = [ "video" "render" ];

  # Automatic db backups
  services.postgresqlBackup = {
    enable = true;
    databases = [ "immich" ];
    location = "/tank/backups/homeserver/postgresql-immich";
  };
}
