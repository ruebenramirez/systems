terraform {
  # secret_wo (main.tf) is a write-only argument: 1.10 parses the syntax but
  # 1.11 is the first release where write-only attributes are usable in
  # resources, so an older tofu fails with "Unsupported argument: secret_wo".
  required_version = ">= 1.11"

  required_providers {
    harbor = {
      source  = "goharbor/harbor"
      version = "~> 3.12"
    }
  }
}
