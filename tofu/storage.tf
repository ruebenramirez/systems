# Local pool on xps17 devpool.
#
# NOTE: the ZFS driver segfaults incusd (raft/cowsql) during large VM disk
# content copies, so the `dir` driver is used instead. The backing directory is
# on the devpool zpool; VM disks are stored as qcow2 files.
resource "incus_storage_pool" "local" {
  name   = local.pool
  driver = "dir"

  config = {
    source = "/devpool/incus-storage"
  }
}
