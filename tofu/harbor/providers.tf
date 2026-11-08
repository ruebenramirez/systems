# Harbor's own API, not the cluster: everything here is Harbor *content*
# (registries, projects, robots, GC). The deployment itself is the Helm release
# declared in nix/machines/_common/services/k3s-harbor.nix.
#
# State is separate from the Incus fleet in ../: this is a service's application
# configuration, and its lifecycle has nothing to do with VMs.
provider "harbor" {
  url      = var.harbor_url
  username = "admin"
  password = var.harbor_admin_password
}
