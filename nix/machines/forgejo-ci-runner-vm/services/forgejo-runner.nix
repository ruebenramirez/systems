{ config, lib, pkgs, pkgs-unstable, ... }:
{

  systemd.services.forgejo-ci-runner = {
    description = "Forgejo Actions Runner";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${pkgs-unstable.forgejo-runner}/bin/act_runner daemon --config /persist/forgejo-ci/config.yaml";
      Restart = "always";

      # Use a fixed user instead of DynamicUser to easily manage group permissions
      User = "forgejo-runner";
      Group = "docker";

      # Ensure state directory is created
      StateDirectory = "forgejo-runner";
    };
  };

  # Explicitly create the user/group
  users.users.forgejo-runner = {
    isSystemUser = true;
    group = "forgejo-runner";
    extraGroups = [ "docker" ];
  };
  users.groups.forgejo-runner = {};

}
