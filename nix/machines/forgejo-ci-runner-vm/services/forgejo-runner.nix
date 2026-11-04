{ config, lib, pkgs, secretFile, ... }:
let
  # Host-mode jobs run as the deploy user so they get the fleet ssh config and
  # deploy key; container jobs are unaffected.
  deployUser = "nixdeploy";
  deployHome = "/var/lib/nixdeploy";
in
{
  sops.secrets.forgejo_runner_uuid = secretFile "forgejo-client-forgejo-ci-runner-vm";
  sops.secrets.forgejo_runner_token = secretFile "forgejo-client-forgejo-ci-runner-vm";

  sops.templates."forgejo-runner-config.yaml" = {
    content = ''
      log:
        level: info

      runner:
        capacity: 1
        labels:
          # Fully qualified: podman resolves a bare `node:22-bookworm` by
          # searching registries.conf (docker.io *and* quay.io here) instead of
          # assuming docker.io the way docker did.
          - docker:docker://docker.io/library/node:22-bookworm
          - ubuntu-latest:docker://docker.io/library/node:22-bookworm
          # `:host` selects the host backend; a bare label silently means the
          # container backend with the default image, which has no nix, no
          # deploy key, no sudo.
          - nixos:host

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
    after = [ "network-online.target" "podman.socket" "sops-nix.service" ];
    wants = [ "network-online.target" "sops-nix.service" ];
    requires = [ "podman.socket" ];
    wantedBy = [ "multi-user.target" ];

    # Host-mode jobs inherit this PATH; nodejs is required for JS actions
    # (`uses:` steps run as `node <action>/dist/index.js`) since there is no
    # container to supply one.
    environment = {
      HOME = deployHome;
      # Container jobs run under podman, which serves the Docker Engine API the
      # runner dials; services/podman.nix sets up the socket and the group.
      DOCKER_HOST = "unix:///run/podman/podman.sock";
      PATH = lib.mkForce (lib.makeBinPath [
        # nix first, to beat stale user-profile copies
        pkgs.nix
        pkgs.git
        pkgs.openssh
        pkgs.coreutils
        pkgs.bash
        pkgs.nodejs
      ] + ":/run/wrappers/bin:/run/current-system/sw/bin:/usr/bin:/bin");
    };

    serviceConfig = {
      ExecStart = "${pkgs.forgejo-runner}/bin/forgejo-runner daemon --config ${config.sops.templates."forgejo-runner-config.yaml".path}";
      Restart = "always";
      RestartSec = 10;
      User = deployUser;
      WorkingDirectory = deployHome;
    };
  };
}
