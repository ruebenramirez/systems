terraform {
  # Floor chosen for the provider rather than for any one argument: 3.12 targets
  # current OpenTofu, and 1.11 is what the fleet's admin host runs. The write-only
  # `secret_wo` that used to force this floor is gone with the robot account.
  required_version = ">= 1.11"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.12"
    }
  }
}
