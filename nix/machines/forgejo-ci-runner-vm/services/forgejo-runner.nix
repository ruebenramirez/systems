{ config, lib, pkgs, ... }:
let
  # Host-mode ("nixos" label) jobs run `nup-fleet --upgrade`, which needs
  # nix, SSH access to the fleet, and passwordless sudo on the targets. The
  # dedicated `nixdeploy` user (see `_common/nix-deploy-user.nix`) has an
  # `~/.ssh/config` for the fleet and holds the deploy key, so the daemon
  # runs as that user. Docker jobs are unaffected -- they still run in
  # containers and never touch the host identity.
  deployUser = "nixdeploy";
  deployHome = "/var/lib/nixdeploy";
in
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
          # Host-mode label: no docker:// scheme, so jobs run directly on
          # this VM. Used by the nightly `nup-fleet --upgrade` workflow,
          # which needs nix, SSH to the fleet, and a writable checkout.
          - nixos

      server:
        connections:
          default:
            url: https://code.rueb.dev/
            uuid: ${config.sops.placeholder.forgejo_runner_uuid}
            token: ${config.sops.placeholder.forgejo_runner_token}
    '';
    mode = "0400";
    owner = deployUser;
    group = "nixdeploy";
    restartUnits = [ "forgejo-ci-runner.service" ];
  };

  systemd.services.forgejo-ci-runner = {
    description = "Forgejo Actions Runner";
    after = [ "network-online.target" "docker.service" "sops-nix.service" ];
    wants = [ "network-online.target" "sops-nix.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    # Host-mode jobs inherit the daemon's environment, and systemd's default
    # PATH has no nix/ssh/git. Give the runner a normal system PATH so
    # `nup-fleet`, `nixos-rebuild`, and `ssh` resolve inside job steps.
    environment = {
      HOME = deployHome;
      PATH = lib.mkForce (lib.makeBinPath [
        # `nix` first so `nix`, `nixos-rebuild`, and `nix-copy-closure` win
        # over any stale user-profile copies.
        pkgs.nix
        pkgs.git
        pkgs.openssh
        pkgs.coreutils
        pkgs.bash
      ] + ":/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin");
    };

    serviceConfig = {
      ExecStart = "${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config ${config.sops.templates."forgejo-runner-config.yaml".path}";
      Restart = "always";
      RestartSec = 10;
      User = deployUser;
      # The daemon needs the docker socket to launch containerized jobs.
      Group = "docker";
      WorkingDirectory = deployHome;
    };
  };
}
