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
| `scripts/stage-libvirt-disks.sh` | Compact a libvirt qcow2 into an Incus image tarball |
| `scripts/build-incus-image.sh` | Build a guest's image via the flake and stage it |
| `scripts/create-vm.sh` | Register the image, create the instance, adopt it |

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

## Adding a new VM

Full guide: [Create a new VM](../docs/incus-vm-management.md#create-a-new-vm).
Define the guest + `flake.nix` entries first, then:

```sh
./scripts/build-incus-image.sh <vm>   # build .#<vm>-incus-image and stage it
# add <vm> to locals.tf, then:
./scripts/create-vm.sh <vm>           # register + create + adopt
```

## Migrating a libvirt VM

```sh
sudo virsh shutdown <vm>
./scripts/stage-libvirt-disks.sh <vm> # compact qcow2 -> <vm>.tar
# add <vm> to locals.tf, then:
./scripts/create-vm.sh <vm>
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
[Create a new VM](../docs/incus-vm-management.md#create-a-new-vm)).