output "proxy_cache_projects" {
  description = "Proxy-cache projects and the pull prefix each one answers to."
  value = {
    for name, project in harbor_project.proxy_cache :
    name => "${var.harbor_url}/${name}"
  }
}

output "robot_ci_name" {
  description = "Login name of the CI robot account (the secret is in systems-secrets, never here)."
  value       = harbor_robot_account.ci.full_name
}
