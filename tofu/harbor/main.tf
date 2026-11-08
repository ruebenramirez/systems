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
  provider_name = "quay"
  name          = "quay"
  endpoint_url  = "https://quay.io"
}

resource "harbor_registry" "gcr" {
  provider_name = "google"
  name          = "gcr"
  endpoint_url  = "https://gcr.io"
}

locals {
  # The project name is what appears in the pull path
  # (harbor.rueb.dev/<project>/<upstream path>), so it is also what
  # my.k3sHarbor.containerdProxyProjects rewrites to and the two must agree.
  proxy_projects = {
    dockerhub = harbor_registry.docker_hub.registry_id
    ghcr      = harbor_registry.ghcr.registry_id
    quay      = harbor_registry.quay.registry_id
    gcr       = harbor_registry.gcr.registry_id
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

# Pull account for CI and anything else that needs an authenticated identity
# against the registry. System-level with pull on every project: the cache is
# public, so this exists for rate-limit-free pulls and for a name in Harbor's
# audit log, not for a permission boundary.
resource "harbor_robot_account" "ci" {
  name        = "ci"
  description = "Fleet pull account (CI, node containerd)"
  level       = "system"
  duration    = 365

  secret_wo         = var.robot_ci_secret
  secret_wo_version = var.robot_ci_secret_version

  permissions {
    kind      = "system"
    namespace = "/"

    access {
      action   = "pull"
      resource = "repository"
    }
  }
}

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
  # robot$ci's secret expires this many days after creation and nothing
  # schedules the rotation docs/harbor.md describes: it is a calendar reminder,
  # not a mechanism.
  robot_token_expiration = 365
  token_expiration       = 30
  session_timeout        = 60
}
