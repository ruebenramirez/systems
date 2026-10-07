# Shared VM base profile. A profile is required because the Incus CLI cannot
# create a VM with no root device (`--no-profiles` fails), and the provider's
# create path times out on large image copies — so instances are created with
# `incus init ... -p vm-base` and then imported into OpenTofu.
resource "incus_profile" "vm_base" {
  name = "vm-base"

  config = {
    "security.secureboot" = "false"
    "boot.autostart"      = "true"
  }

  device {
    name = "root"
    type = "disk"

    properties = {
      pool = incus_storage_pool.local.name
      path = "/"
    }
  }
}