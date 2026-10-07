terraform {
  required_version = ">= 1.8"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.2"
    }
  }
}
