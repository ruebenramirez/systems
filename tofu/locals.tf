locals {
  bridge = "br0"
  pool   = "local"
  stage  = "/devpool/incus-migration"

  vms = {
    "dev-vm-xps" = {
      vcpus     = 8
      memory    = "8192MiB"
      mac       = "52:54:00:07:c2:28"
      image_dir = "${local.stage}/dev-vm-xps.tar"
    }
    "download-vm-xps" = {
      vcpus     = 2
      memory    = "4096MiB"
      mac       = "52:54:00:40:72:56"
      image_dir = "${local.stage}/download-vm-xps.tar"
    }
    "forgejo-ci-runner-vm" = {
      vcpus     = 4
      memory    = "4096MiB"
      mac       = "52:54:00:1b:30:3b"
      image_dir = "${local.stage}/forgejo-ci-runner-vm.tar"
    }
    "nginx-vm" = {
      vcpus     = 1
      memory    = "512MiB"
      mac       = "52:54:00:80:00:01"
      image_dir = "${local.stage}/nginx-vm.tar"
    }
  }
}