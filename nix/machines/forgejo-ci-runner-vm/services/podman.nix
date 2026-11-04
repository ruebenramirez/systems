{ config, lib, ... }:
{
  # The Actions runner's container backend is Podman, reached over the Docker
  # Engine API forgejo-runner already speaks -- `docker://` labels work
  # unchanged, only the socket behind them moves.
  #
  # Rootful on purpose: `nixdeploy` already has NOPASSWD sudo on this host
  # (_common/nix-deploy-user.nix), so a rootless engine would buy uid-mapped
  # bind mounts in job workspaces rather than a narrower blast radius. Revisit
  # it together with narrowing that sudo.
  virtualisation.docker = {
    enable = lib.mkForce false;
    enableOnBoot = lib.mkForce false;
  };

  # kubernetes.nix sets a unitConfig on docker.service unconditionally, which
  # leaves an enabled stub unit behind once the package is gone.
  systemd.services.docker.enable = lib.mkForce false;

  virtualisation.podman = {
    enable = true;

    # Serves /run/podman/podman.sock and symlinks /run/docker.sock to it, so a
    # job that shells out to a hardcoded docker path still finds an engine.
    dockerSocket.enable = true;

    # Job images and build cache land on the same 500G disk as the nix store.
    # Prune takes dangling images and build cache only; the runner pulls
    # whatever image a job asks for.
    autoPrune.enable = true;
  };

  # The API socket is 0660 root:podman.
  users.users.nixdeploy.extraGroups = [ "podman" ];
}
