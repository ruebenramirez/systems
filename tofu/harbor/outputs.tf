output "proxy_cache_projects" {
  description = "Proxy-cache projects and the pull prefix each one answers to."
  value = {
    for name, project in harbor_project.proxy_cache :
    name => "${var.harbor_url}/${name}"
  }
}
