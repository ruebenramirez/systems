# Harbor proxy-cache mirrors for every container engine on this host that reads
# /etc/containers/registries.conf -- Podman, the Docker-compatible clients, and
# skopeo (issue #51).
#
# skopeo is the reason this is not just a Podman concern: `pkgs.dockerTools.pullImage`
# is `skopeo copy docker://<image>@<digest>`, so the images this flake builds
# into a system closure (forgejo, webmail, wordpress, mariadb, hermes-agent) are
# fetched by skopeo on whatever host does the build -- `fwai0`, the fleet's
# builder. Without this drop-in there, those fetches are the one remaining pull
# path that goes straight to the upstream and straight into Docker Hub's
# anonymous per-IP rate limit.
#
# The k3s nodes do not need it: containerd reads k3s' own registries.yaml, which
# services/k3s-harbor.nix writes from the same list.
{ config, lib, ... }:
let
  cfg = config.my.containerMirrors;
  mirrors = import ../../lib/registry-mirrors.nix;
  # registries.conf mirror locations carry no scheme: host/path, not a URL.
  hostPath = m: "${mirrors.host}/${m.project}";
in
{
  options.my.containerMirrors.enable = lib.mkEnableOption "the Harbor proxy cache as a registry mirror for podman, docker and skopeo on this host";

  config = lib.mkIf cfg.enable {
    # A drop-in rather than `virtualisation.containers.registries`: that option
    # only writes the `[registries]` table (search/insecure/block), and mirrors
    # need `[[registry]]` entries, which the module cannot express -- writing
    # /etc/containers/registries.conf directly would fight the module's own
    # `environment.etc` entry. containers-common reads this directory after the
    # main file, so the two compose instead of overwriting each other.
    #
    # `mirror-by-digest-only = false` is the default and is left alone: it is what
    # makes a plain `podman pull docker.io/library/nginx` go to
    # harbor.rueb.dev/dockerhub/library/nginx. Digest-only pulls -- every
    # `dockerTools.pullImage` -- use the mirror either way. Mirrors are tried
    # before the upstream and failure falls through to it, so an unreachable
    # Harbor (a host off the tailnet, say) costs a failed connection per pull
    # rather than failing the pull.
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
  };
}
