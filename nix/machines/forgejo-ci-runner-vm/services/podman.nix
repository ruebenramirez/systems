{ lib, ... }:
let
  mirrors = import ../../../lib/registry-mirrors.nix;
  # registries.conf mirror locations carry no scheme: host/path, not a URL.
  hostPath = m: "${mirrors.host}/${m.project}";
in
{
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

  # Pulls go through the Harbor proxy cache first (issue #51), so a Docker Hub
  # rate limit or an upstream outage does not fail a job.
  #
  # A drop-in rather than `virtualisation.containers.registries`: that option
  # only writes the `[registries]` table (search/insecure/block), and mirrors
  # need `[[registry]]` entries, which the module cannot express -- writing
  # /etc/containers/registries.conf directly would fight the module's own
  # `environment.etc` entry. containers-common reads this directory after the
  # main file, so the two compose instead of overwriting each other.
  #
  # `mirror-by-digest-only = false` is the default and is left alone: it is what
  # makes a plain `podman pull docker.io/library/nginx` go to
  # harbor.rueb.dev/dockerhub/library/nginx. Containers' mirror fallback stays
  # on, so an unreachable Harbor pulls from the upstream instead of failing.
  environment.etc."containers/registries.conf.d/20-harbor-mirrors.conf" =
    lib.mkIf (mirrors.projects != [ ])
      {
        text = lib.concatMapStrings (m: ''
          [[registry]]
          prefix = "${m.registry}"
          location = "${m.registry}"

          [[registry.mirror]]
          location = "${hostPath m}"

        '') mirrors.projects;
      };

  # The API socket is 0660 root:podman.
  users.users.nixdeploy.extraGroups = [ "podman" ];
}
