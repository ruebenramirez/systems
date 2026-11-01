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
    "hermes-vm-xps" = {
      vcpus     = 4
      memory    = "8192MiB"
      mac       = "52:54:00:68:65:72"
      image_dir = "${local.stage}/hermes-vm-xps.tar"
    }
    // k3s cluster nodes: 4 vCPU / 6 GiB each, not the 8 GiB the issue proposed --
    // see nix/machines/_common/k3s-node.nix for the memory arithmetic.
    "k3s-1" = {
      vcpus     = 4
      memory    = "6144MiB"
      mac       = "52:54:00:6b:33:01"
      image_dir = "${local.stage}/k3s-1.tar"
    }
    "k3s-2" = {
      vcpus     = 4
      memory    = "6144MiB"
      mac       = "52:54:00:6b:33:02"
      image_dir = "${local.stage}/k3s-2.tar"
    }
    "k3s-3" = {
      vcpus     = 4
      memory    = "6144MiB"
      mac       = "52:54:00:6b:33:03"
      image_dir = "${local.stage}/k3s-3.tar"
    }
  }
}
