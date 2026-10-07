# xps17 Incus VM fleet (OpenTofu)

Declarative definition of the VM guests running under Incus on `xps17`.

See [`docs/incus-vm-management.md`](../docs/incus-vm-management.md) for the full
operator guide; this file is the short in-directory runbook.

## Layout

| File | Purpose |
|------|---------|
| `versions.tf` | OpenTofu + `lxc/incus` provider pin |
| `providers.tf` | Local Incus unix-socket provider |
| `locals.tf` | VM inventory (vCPU, memory, MAC, staged image path) |
| `storage.tf` | `local` dir pool on `/devpool/incus-storage` |
| `profiles.tf` | `vm-base` profile (root disk, secureboot=false, autostart) |
| `images.tf` | Unified Incus VM images (from staged `.tar` files) |
| `instances.tf` | The VM instances (limits + eth0) |
| `outputs.tf` | Running state |
| `scripts/stage-libvirt-disks.sh` | Package + compact qcow2 into Incus image tarballs |

## Prerequisites on xps17

```sh
incus config get storage.images_volume   # must be local/incus-images (keeps images off root)
```

If unset:

```sh
incus storage volume create local incus-images
incus config set storage.images_volume local/incus-images
```

## State

Local state (`terraform.tfstate`) lives in this directory and is gitignored.
Run on `xps17` as a user in `incus-admin`. `.terraform.lock.hcl` is committed.

## Adding / migrating a VM

```sh
# 1. shut the libvirt domain down, then stage a compact Incus image:
./scripts/stage-libvirt-disks.sh <vm>

# 2. add <vm> to locals.tf, then register the image:
tofu apply -target='incus_image.vm["<vm>"]'

# 3. create the instance with the CLI and adopt it into state:
fp=$(incus image list --format csv --columns fd | grep <vm> | cut -d, -f1)
incus init local:$fp <vm> --vm -p vm-base
incus config set <vm> limits.cpu=<n>
incus config set <vm> limits.memory=<MiB>MiB
incus config device add <vm> eth0 nic nictype=bridged parent=br0 hwaddr=<mac>
incus start <vm>
tofu import 'incus_instance.vm["<vm>"]' "<vm>,image=$fp"
tofu plan     # expect: no changes
```

Instances are created with the Incus CLI + `tofu import` because the provider's
create path is unreliable for large VM disks (websocket drop / `incusd` raft
segfault), and the CLI needs a profile to find a root device.

## Removing a VM

```sh
tofu state rm 'incus_instance.vm["<vm>"]' 'incus_image.vm["<vm>"]'
incus delete <vm> --force
```

Also drop it from `locals.tf`, `flake.nix`, and `nup-fleet`'s `MACHINES`.

## Backups

VM roots are treated as rebuildable/disposable: there are **no snapshots of
`devpool`** and the original qcow2s are rollback-only. Durable data lives on
`homeserver` `tank` and is mounted over NFS (see
[Backups & recovery](../docs/incus-vm-management.md#backups--recovery) and
[Building a fresh Incus image](../docs/incus-vm-management.md#building-a-fresh-incus-image)).