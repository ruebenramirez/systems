resource "incus_instance" "vm" {
  for_each = local.vms

  name     = each.key
  type     = "virtual-machine"
  image    = incus_image.vm[each.key].fingerprint
  profiles = [incus_profile.vm_base.name]
  running  = true

  config = {
    "limits.cpu"    = tostring(each.value.vcpus)
    "limits.memory" = each.value.memory
  }

  device {
    name = "eth0"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = local.bridge
      hwaddr  = each.value.mac
    }
  }

  # Guard against accidental replacement from image/config churn.
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [incus_storage_pool.local, incus_profile.vm_base]
}