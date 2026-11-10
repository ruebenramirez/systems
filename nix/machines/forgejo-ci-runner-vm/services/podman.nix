{ ... }:
{
  imports = [ ../../_common/container-mirrors.nix ];

  # The Actions runner's container backend is Podman, reached through the Docker
  # Engine API it serves, which is what the `docker://` labels speak.
  #
  # Rootful on purpose: `nixdeploy` already has NOPASSWD sudo on this host
  # (_common/nix-deploy-user.nix), so a rootless engine would buy uid-mapped
  # bind mounts in job workspaces rather than a narrower blast radius. Revisit
  # it together with narrowing that sudo.
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

  # Job pulls go through the Harbor proxy cache first (issue #51), so a Docker
  # Hub rate limit or an upstream outage does not fail a job.
  my.containerMirrors.enable = true;

  # The API socket is 0660 root:podman.
  users.users.nixdeploy.extraGroups = [ "podman" ];
}
