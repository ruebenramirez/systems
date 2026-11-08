variable "harbor_url" {
  type        = string
  description = "Base URL of the Harbor instance, as clients reach it."
  default     = "https://harbor.rueb.dev"
}

variable "harbor_admin_password" {
  type        = string
  description = "Harbor admin password. From secrets/harbor-shared.yaml (key harbor-admin-password)."
  sensitive   = true
}

variable "robot_ci_secret" {
  type        = string
  description = "Secret for the robot$ci pull account. From secrets/harbor-shared.yaml (key harbor-robot-ci-secret)."
  sensitive   = true
}

# Bump to push a new value through `secret_wo`; write-only arguments have no
# state to diff, so the version is what makes the provider re-send it.
variable "robot_ci_secret_version" {
  type        = number
  description = "Change to rotate robot_ci_secret into Harbor."
  default     = 1
}

# Docker Hub pulls through the proxy cache are anonymous unless these are set:
# anonymous pulls from Docker Hub are rate-limited per source IP, and the whole
# cluster shares one egress address. Empty means "leave the endpoint uncredentialed".
variable "dockerhub_username" {
  type        = string
  description = "Docker Hub username for the proxy-cache endpoint. Empty leaves the endpoint anonymous."
  default     = ""
}

variable "dockerhub_password" {
  type        = string
  description = "Docker Hub access token for the proxy-cache endpoint. Empty leaves the endpoint anonymous."
  default     = ""
  sensitive   = true
}

# Harbor gives every proxy-cache project a 7-day retention on creation, and a
# second policy added here would sit beside it rather than replace it -- the
# shorter of the two is what actually evicts. 0 therefore means "leave Harbor's
# own rule alone", which is the right answer for a cache whose job is to bound
# disk use. Set it to N (and delete Harbor's auto-created policy first) only if
# a longer cache window is genuinely wanted.
variable "proxy_retention_days" {
  type        = number
  description = "Days of un-pulled cache to keep. 0 leaves Harbor's built-in 7-day proxy-cache retention in place."
  default     = 0
}

variable "gc_schedule" {
  type        = string
  description = "Garbage-collection schedule: a Harbor preset (Daily, Weekly, Monthly, None) or a cron string."
  default     = "Weekly"
}
