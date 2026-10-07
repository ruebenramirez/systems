# Each powered-off libvirt qcow2 is staged as a unified Incus VM image
# (metadata.yaml + rootfs.img) by scripts/stage-libvirt-disks.sh.
resource "incus_image" "vm" {
  for_each = local.vms

  source_file = {
    data_path = each.value.image_dir
  }
}
