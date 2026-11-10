# Upstream registries to pull through. `provider_name` picks Harbor's built-in
# adapter (it knows each registry's auth dance); the endpoint is what the
# adapter dials. Only Docker Hub needs a credential, and only to escape the
# anonymous per-IP rate limit that a single-egress cluster trips over.
resource "harbor_registry" "docker_hub" {
  provider_name = "docker-hub"
  name          = "docker-hub"
  endpoint_url  = "https://hub.docker.com"

  access_id     = var.dockerhub_username == "" ? null : var.dockerhub_username
  access_secret = var.dockerhub_password == "" ? null : var.dockerhub_password
}

resource "harbor_registry" "ghcr" {
  provider_name = "github"
  name          = "ghcr"
  endpoint_url  = "https://ghcr.io"
}

resource "harbor_registry" "quay" {
  # `quay` is a replication adapter, not a proxy-cache one: a project with this
  # registry id fails "unsupported registry type quay". quay.io speaks the
  # Docker Registry v2 API, so the generic adapter proxies it fine.
  provider_name = "docker-registry"
  name          = "quay"
  endpoint_url  = "https://quay.io"
}

resource "harbor_registry" "k8s" {
  # Upstream Kubernetes' registry: kube-state-metrics and the `kubectl` init
  # container from kube-prometheus-stack, and every csi-driver-nfs image.
  #
  # Plain v2 with an anonymous bearer token service, so the generic adapter takes
  # it. Note manifests 307-redirect offsite (registry.k8s.io fronts a Google
  # Artifact Registry bucket): the proxy has to follow that redirect, which is
  # the first thing to check if `k8s/...` pulls come back "not found".
  provider_name = "docker-registry"
  name          = "k8s"
  endpoint_url  = "https://registry.k8s.io"
}

resource "harbor_registry" "codeberg" {
  # forgejo's own registry, pulled at build time by dockerTools.pullImage.
  # Gitea speaks v2 with an anonymous bearer token, same as quay.
  provider_name = "docker-registry"
  name          = "codeberg"
  endpoint_url  = "https://codeberg.org"
}

locals {
  # The project name is what appears in the pull path
  # (harbor.rueb.dev/<project>/<upstream path>), so it is also what
  # my.k3sHarbor.containerdProxyProjects rewrites to and the two must agree.
  # scripts/check-registry-mirrors.sh fails CI when they do not.
  #
  # gcr.io is deliberately absent. Harbor's `google` registry adapter will not
  # validate an anonymous endpoint -- creating it fails "the registry is
  # unhealthy" even though gcr.io answers /v2/ from inside the cluster -- and
  # Google has sunset gcr.io for new content anyway. Kubernetes' registry is
  # registry.k8s.io, a different host, and it is the `k8s` project below.
  proxy_projects = {
    dockerhub = harbor_registry.docker_hub.registry_id
    ghcr      = harbor_registry.ghcr.registry_id
    quay      = harbor_registry.quay.registry_id
    k8s       = harbor_registry.k8s.registry_id
    codeberg  = harbor_registry.codeberg.registry_id
  }
}

# A project with `registry_id` set is a proxy cache: nothing can be pushed to it,
# and a pull for anything not cached is fetched from the endpoint and stored.
#
# Public on purpose -- containerd and podman pull these anonymously, and every
# artifact in them came from a public registry to begin with. Requiring a login
# would mean shipping credentials to every node for no access-control gain.
#
# Scanning is off: these are pass-through caches of public images, and scanning
# on each cold pull would put Trivy's work in the latency path of every first
# fetch without ever changing what is served.
resource "harbor_project" "proxy_cache" {
  for_each = local.proxy_projects

  name                   = each.key
  registry_id            = each.value
  public                 = true
  vulnerability_scanning = false
  storage_quota          = -1
}

resource "harbor_retention_policy" "proxy_cache" {
  # Keyed on the project name rather than an index into values(...), so adding or
  # removing an upstream cannot silently re-bind a policy to the wrong project.
  for_each = var.proxy_retention_days > 0 ? local.proxy_projects : {}

  scope    = harbor_project.proxy_cache[each.key].id
  schedule = "Daily"

  rule {
    repo_matching          = "**"
    tag_matching           = "**"
    n_days_since_last_pull = var.proxy_retention_days
  }
}

# No robot account. The cache is public and every node pulls anonymously, so
# there is nothing for one to grant: Harbor rejects `repository:pull` on a
# system-level robot outright ("bad request permission: repository:pull" --
# `repository` is not a system resource in 2.15), and a project-scoped robot
# would only be worth having once something private exists to pull from.
# `harbor-robot-ci-secret` in systems-secrets is therefore unused; it returns
# with the robot when there is a private project that needs one.

# GC is what actually returns space to the tank: deleting tags (retention does
# that) only unlinks manifests; GC reclaims the blobs they held.
resource "harbor_garbage_collection" "weekly" {
  schedule        = var.gc_schedule
  delete_untagged = true
  workers         = 1
}

resource "harbor_config_system" "fleet" {
  # Projects are created here by code, not by hand: a self-service project turns
  # the shared cache into N untracked namespaces nobody is watching the quota of.
  #
  # Self-registration is *not* closed off alongside this: provider 3.12.5 has no
  # `self_registration` attribute, so Harbor's default (on) stands. Anyone who
  # can reach the API can still create accounts -- they just cannot create
  # projects. Closing it needs the Harbor UI/API config or a provider bump.
  project_creation_restriction = "adminonly"
  token_expiration             = 30
  session_timeout              = 60
}
