{ config, pkgs, ... }:

{
  # This configuration has been simplified since password files
  # are managed through /persist directory.
  #
  # Expected files in /persist:
  # - /persist/nextcloud/admin-pass
  # - /persist/nextcloud/db-pass (if using external DB authentication)
  # - /persist/nextcloud/nextcloud-secrets.json (if using secretFile)

  # If you want to use SOPS-nix with /persist, you can configure it like:
  #
  # imports = [
  #   <sops-nix/modules/sops>
  # ];
  #
  # sops = {
  #   defaultSopsFile = ./secrets.yaml;
  #   secrets = {
  #     nextcloud-admin-password = {
  #       path = "/persist/nextcloud/admin-pass";
  #       mode = "0600";
  #       owner = "nextcloud";
  #       group = "nextcloud";
  #     };
  #   };
  # };

  # Nextcloud configuration using /persist files
  services.nextcloud = {
    config = {
      adminpassFile = "/persist/nextcloud/admin-pass";
      # dbpassFile = "/persist/nextcloud/db-pass";  # If needed
    };
    # secretFile = "/persist/nextcloud/nextcloud-secrets.json";  # If needed
  };
}
