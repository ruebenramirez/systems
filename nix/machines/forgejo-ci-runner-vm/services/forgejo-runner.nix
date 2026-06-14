  { config, lib, pkgs, pkgs-unstable, ... }:
  {
    systemd.services.forgejo-ci-runner = {
      description = "Forgejo Actions Runner";
      after = [ "network.target" "docker.service" ];
      requires = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.bash
        pkgs.coreutils
        pkgs.git
        pkgs.gnugrep
        pkgs.gnused
        pkgs.nix
        pkgs.nodejs_22
      ];

      environment = {
        HOME = "/var/lib/forgejo-runner";
        XDG_CACHE_HOME = "/var/lib/forgejo-runner/.cache";
      };

      serviceConfig = {
        ExecStart = "${pkgs-unstable.forgejo-runner}/bin/act_runner daemon --config /persist/forgejo-ci/config.yaml";
        Restart = "always";
        User = "forgejo-runner";
        Group = "docker";
        StateDirectory = "forgejo-runner";
      };
    };

    users.users.forgejo-runner = {
      isSystemUser = true;
      group = "forgejo-runner";
      extraGroups = [ "docker" ];
      home = "/var/lib/forgejo-runner";
      createHome = true;
    };

    users.groups.forgejo-runner = {};
  }

