# The fleet's container-image proxy cache, in one place.
#
# Three very different consumers read it:
#
#   - the k3s nodes get containerd mirror rewrites
#     (`nix/machines/_common/services/k3s-harbor.nix`), which is what pod images
#     and the Helm charts' images pull through;
#   - any host running Podman gets a registries.conf drop-in
#     (`nix/machines/_common/container-mirrors.nix`);
#   - so does the build host, because `pkgs.dockerTools.pullImage` is a wrapper
#     around `skopeo copy docker://...` and skopeo reads the same registries.conf
#     -- that is what puts the nix-built images (`pullImage` in
#     `homeserver/srv/forgejo.nix`, `ssdnodes-1/srv/wordpress.nix`,
#     `hermes-vm-xps/services/hermes-agent.nix`) behind the cache too.
#
# All of them have to agree on the hostname and on the project name each upstream
# is cached under, because those two strings are what the rewritten pull path is
# made of -- so they are written once, here.
#
# Plain Nix (no `lib`, no module system), like inventory.nix: it is read from
# module defaults and must stay evaluable on its own -- `scripts/check-registry-mirrors.sh`
# evaluates it directly to diff it against `tofu/harbor/main.tf`.
#
# `registry` is the upstream exactly as it appears in an image reference;
# `project` is the Harbor proxy-cache project that fronts it, which must also
# exist in Harbor itself (`tofu/harbor/main.tf` builds the same list).
rec {
  host = "harbor.rueb.dev";

  # Mirrors are pull-through caches of public upstreams, so pulls stay
  # anonymous: everything in them came from a public registry to begin with.
  projects = [
    # k3s' own system images (rancher/mirrored-*), Traefik, the Harbor chart
    # (goharbor/*), Grafana and its init containers, the CI runner's node image,
    # and the wordpress/mariadb/hermes-agent images built into closures.
    {
      registry = "docker.io";
      project = "dockerhub";
    }
    # Gatus, bulwarkmail/webmail, halogen-flash-server, and
    # kube-prometheus-stack's kube-webhook-certgen.
    {
      registry = "ghcr.io";
      project = "ghcr";
    }
    # The prometheus-operator family: prometheus, alertmanager, thanos,
    # node-exporter, kube-rbac-proxy, k8s-sidecar, blackbox-exporter.
    {
      registry = "quay.io";
      project = "quay";
    }
    # Upstream Kubernetes' own registry: kube-state-metrics and the `kubectl`
    # init container in kube-prometheus-stack, and every csi-driver-nfs image
    # (nfsplugin plus its csi-provisioner/resizer/snapshotter sidecars).
    {
      registry = "registry.k8s.io";
      project = "k8s";
    }
    # Only forgejo, and only at build time: `dockerTools.pullImage` on the
    # builder is the one pull path here that does not go through a container
    # engine, so it needs the registries.conf mirror to be cached at all.
    {
      registry = "codeberg.org";
      project = "codeberg";
    }
  ];
}
