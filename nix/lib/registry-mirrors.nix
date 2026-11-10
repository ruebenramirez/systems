# The fleet's container-image proxy cache, in one place.
#
# Two very different consumers read it: the k3s nodes get containerd mirror
# rewrites (`nix/machines/_common/services/k3s-harbor.nix`) and any host running
# Podman gets a registries.conf drop-in
# (`nix/machines/forgejo-ci-runner-vm/services/podman.nix`). Both have to agree
# on the hostname and on the project name each upstream is cached under, because
# those two strings are what the rewritten pull path is made of -- so they are
# written once, here.
#
# Plain Nix (no `lib`, no module system), like inventory.nix: it is read from
# module defaults and must stay evaluable on its own.
#
# `registry` is the upstream exactly as it appears in an image reference;
# `project` is the Harbor proxy-cache project that fronts it, which must also
# exist in Harbor itself (`tofu/harbor/main.tf` builds the same list).
rec {
  host = "harbor.rueb.dev";

  # Mirrors are pull-through caches of public upstreams, so pulls stay
  # anonymous: everything in them came from a public registry to begin with.
  projects = [
    {
      registry = "docker.io";
      project = "dockerhub";
    }
    {
      registry = "ghcr.io";
      project = "ghcr";
    }
    {
      registry = "quay.io";
      project = "quay";
    }
  ];
}
