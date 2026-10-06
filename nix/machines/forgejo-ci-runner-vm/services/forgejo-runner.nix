{ config, pkgs, ... }:
{
  sops.secrets.forgejo_runner_uuid = { };
  sops.secrets.forgejo_runner_token = { };

  sops.templates."forgejo-runner-config.yaml" = {
    content = ''
      log:
        level: info

      runner:
        capacity: 1
        labels:
          - docker:docker://node:22-bookworm
          - ubuntu-latest:docker://node:22-bookworm

      server:
        connections:
          default:
            url: https://code.rueb.dev/
            uuid: ${config.sops.placeholder.forgejo_runner_uuid}
            token: ${config.sops.placeholder.forgejo_runner_token}
    '';
    mode = "0400";
    owner = "forgejo-runner";
    group = "forgejo-runner";
    restartUnits = [ "forgejo-ci-runner.service" ];
  };

  systemd.services.forgejo-ci-runner = {
    description = "Forgejo Actions Runner";
    after = [ "network-online.target" "docker.service" "sops-nix.service" ];
    wants = [ "network-online.target" "sops-nix.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    environment.HOME = "/var/lib/forgejo-runner";

    serviceConfig = {
      ExecStart = "${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config ${config.sops.templates."forgejo-runner-config.yaml".path}";
      Restart = "always";
      RestartSec = 10;
      User = "forgejo-runner";
      Group = "docker";
      SupplementaryGroups = [ "docker" ];
      StateDirectory = "forgejo-runner";
      WorkingDirectory = "/var/lib/forgejo-runner";
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