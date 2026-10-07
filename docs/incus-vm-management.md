# Incus VMs on xps17

I run the guest VMs on `xps17` under [Incus](https://linuxcontainers.org/incus/).
The instances and their CPU/memory/networking are declared with OpenTofu in
[`tofu/`](../tofu/); the guests themselves are NixOS systems I update in place
with [`nup-fleet`](../dotfiles/bin/nup-fleet).

Run everything here **on `xps17`** as `rramirez` (member of `incus-admin`).

## The fleet

| VM | vCPU | RAM | Disk (provisioned) | MAC | LAN IP |
|----|------|-----|--------------------|-----|--------|
| `dev-vm-xps` | 8 | 8192 MiB | 200 GiB | `52:54:00:07:c2:28` | `192.168.8.165` |
| `download-vm-xps` | 2 | 4096 MiB | 250 GiB | `52:54:00:40:72:56` | `192.168.8.176` |
| `forgejo-ci-runner-vm` | 4 | 4096 MiB | 500 GiB | `52:54:00:1b:30:3b` | `192.168.8.230` |

Provisioned sizes are just the virtual disk sizes; the qcow2 files are sparse and
compressed far below that (e.g. `dev` runs ~25 GiB on disk for ~60 GiB of data).

```sh
incus list
incus info dev-vm-xps
incus console dev-vm-xps            # add --show-log to dump the boot log
incus exec dev-vm-xps -- ip -br addr
```

SSH (put these in `~/.ssh/config`):

```text
Host dev-vm-xps-lan
  HostName 192.168.8.165
  User rramirez
  IdentityFile ~/.ssh/id_ed25519
```

Guests also join the tailnet, so `ssh dev-vm-xps` works — **except
`download-vm-xps`, which runs Mullvad and blocks inbound tailnet SSH**; reach it
over the LAN or with `incus exec`.

## Updating a guest

The VM image is just the seed; day-to-day changes (packages, services, apps) are
normal NixOS rebuilds inside the guest:

```sh
nup-fleet --upgrade dev-vm-xps   # flake update + rebuild
nup-fleet dev-vm-xps             # rebuild only
```

`nup-fleet` uses `ssh <name>` (the tailnet), so `download-vm-xps` needs the LAN
fallback:

```sh
nixos-rebuild switch --flake ~/code/systems#download-vm-xps \
  --target-host rramirez@192.168.8.176 --sudo --no-reexec
```

### Changing CPU / RAM

Edit the VM in [`tofu/locals.tf`](../tofu/locals.tf), then:

```sh
cd ~/code/systems/tofu
tofu plan && tofu apply
```

`limits.memory` is a hard cap. `limits.cpu` changes may need a VM restart.
Instances have `lifecycle { prevent_destroy = true }`, so a bad edit fails the
apply instead of nuking the VM.

## Storage

- Instance roots: Incus **`dir`** pool `local`, backed by the directory
  **`/devpool/incus-storage`** on the `devpool` zpool. VM roots are plain qcow2
  files (`.../virtual-machines/<vm>/root.img`), so there is **no per-VM ZFS
  dataset and no ZFS snapshots** of them.
- Images: a dedicated custom volume **`local/incus-images`**, selected with the
  Incus server setting `storage.images_volume`. This matters: without it, imported
  images land in `/var/lib/incus/images` on the *root* pool and can fill `/`.

```sh
incus storage list
incus storage volume list local
zfs list -o space devpool
incus config get storage.images_volume     # local/incus-images
```

### TRIM / qcow2 size

I verified discard passes through for Incus VM disks: writing 2 GiB of random
data grew `dev`'s `root.img` from 25048 → 26717 MiB, and after `rm` + `fstrim`
it dropped back to 25444 MiB. Guests run `fstrim.timer`, so freed blocks get
reclaimed automatically. If a disk ever balloons, check with:

```sh
incus exec dev-vm-xps -- fstrim -av
sudo du -m /devpool/incus-storage/virtual-machines/dev-vm-xps/root.img
```

(The original VMs bloated to hundreds of GiB because libvirt's qcow2 disks had no
`discard='unmap'`; that is fixed under Incus.)

## Backups & recovery

The VMs are **disposable/rebuildable** — I don't back up their root disks. There
are deliberately no snapshots on `devpool`; treat a broken VM as "re-stage or
rebuild it", not "restore it".

What *is* durable:

- The only data worth keeping lives on `homeserver` `tank` (Sanoid snapshots +
  `syncoid` to `pi-syncoid-target`) and is mounted into a guest over NFS. For
  `dev-vm-xps` that's `/mnt/data` (`/tank/vm-nfs-shares/dev-vm-xps/data`).
- `dev`/`forgejo`/`download` root filesystems hold only rebuildable state
  (Nix store, Docker images, torrents, CI caches).

The original libvirt qcow2s under `/devpool/VMs/images/` are a one-time rollback
lever, not a backup — delete them once I'm confident.

To rebuild a VM from scratch: build a fresh image (below) and create the instance,
or re-stage a libvirt qcow2 with `tofu/scripts/stage-libvirt-disks.sh`.

## NFS shares from homeserver `tank`

Server layout is `/tank/vm-nfs-shares/<host>/<mount>/` — plain directories in the
`tank/data` dataset, so Sanoid + syncoid cover them automatically. The parent is
exported once with `fsid=0,crossmnt` to `192.168.8.0/24`. Today only `dev-vm-xps`
mounts `data` at `/mnt/data`.

Add a share with two small edits:

```nix
# nix/machines/homeserver/configuration.nix
my.vmNfsServer = { enable = true; shares."dev-vm-xps" = [ "data" ]; };
```
```nix
# the guest's configuration.nix
my.vmNfsClient.mounts.data = { };     # -> /mnt/data
```

then `nup-fleet --upgrade homeserver` and `nup-fleet --upgrade <guest>`.

## Adding a VM

1. **Guest config.** Add `nix/machines/<vm>/configuration.nix` importing
   `../_common/qemu-vm-guest.nix` (for `eth0` + incus-agent) and, if it needs
   tank data, `../_common/vm-nfs-client.nix`. Add it to `nixosConfigurations` in
   `flake.nix`, and add `<vm>` to `MACHINES` in
   [`dotfiles/bin/nup-fleet`](../dotfiles/bin/nup-fleet).
2. **Image.** Build (below) or stage a compact image tarball.
3. **Inventory.** Add the VM to `tofu/locals.tf` (vcpus, memory, mac, image_dir).
4. **Register + create + adopt:**
   ```sh
   cd ~/code/systems/tofu
   tofu apply -target='incus_image.vm["<vm>"]'
   fp=$(incus image list --format csv --columns fd | grep <vm> | cut -d, -f1)
   incus init local:$fp <vm> --vm -p vm-base
   incus config set <vm> limits.cpu=<n>
   incus config set <vm> limits.memory=<MiB>MiB
   incus config device add <vm> eth0 nic nictype=bridged parent=br0 hwaddr=<mac>
   incus start <vm>
   tofu import 'incus_instance.vm["<vm>"]' "<vm>,image=$fp"
   tofu plan            # expect: no changes
   ```

The instance is created with the **Incus CLI and imported**, not created by the
provider: the `lxc/incus` provider's create path drops the websocket / segfaults
`incusd` on large disk copies, and the CLI can't create a VM without a profile —
hence the `vm-base` profile (root disk + `secureboot=false` + `autostart`).

## Removing a VM

```sh
cd ~/code/systems/tofu
tofu state rm 'incus_instance.vm["<vm>"]' 'incus_image.vm["<vm>"]'
incus delete <vm> --force
incus image delete <fingerprint>
```

then drop it from `tofu/locals.tf`, `flake.nix`, and `nup-fleet` `MACHINES`.

## Building a fresh Incus image

Tested end to end on `xps17`. Use nixpkgs' incus VM profile instead of disko:

1. Guest config imports the profile:
   ```nix
   imports = [ (modulesPath + "/virtualisation/incus-virtual-machine.nix") ];
   networking.hostName = "<vm>";
   ```
   (That profile enables `virtualisation.incus.agent` and sets
   `system.build.qemuImage`.)
2. Build the disk and metadata:
   ```sh
   qcowdir=$(nix build --no-link --print-out-paths .#nixosConfigurations.<vm>.config.system.build.qemuImage)
   metadir=$(nix build --no-link --print-out-paths .#nixosConfigurations.<vm>.config.system.build.metadata)
   ```
3. Package a unified image (`metadata.yaml` + `rootfs.img`) — the provider needs a
   **file**, not a directory:
   ```sh
   work=$(mktemp -d)
   tar -xf "$metadir"/tarball/*.tar.xz -C "$work" metadata.yaml
   qemu-img convert -c -O qcow2 "$qcowdir"/nixos.qcow2 "$work/rootfs.img"
   tar -C "$work" -cf /tmp/<vm>.tar metadata.yaml rootfs.img
   ```
4. Import and create:
   ```sh
   scp /tmp/<vm>.tar xps17:/tmp/
   ssh xps17 'incus image import /tmp/<vm>.tar'      # or a tofu incus_image resource
   ```
   Then follow the create/adopt steps above.

Note: the stock profile uses predictable NIC names (e.g. `enp5s0`). Import
`qemu-vm-guest.nix` (which sets `net.ifnames=0` → `eth0`) if I want the migrated
guests' naming.

## Migrating a libvirt VM (one-time)

The original 3 guests were migrated from libvirt/KVM. Recipe, still useful if a
libvirt qcow2 needs importing:

```sh
sudo virsh shutdown <vm>
cd ~/code/systems/tofu
./scripts/stage-libvirt-disks.sh <vm>      # compacts qcow2 -> <vm>.tar
tofu apply -target='incus_image.vm["<vm>"]'
# then the CLI create + tofu import steps above
```

`stage-libvirt-disks.sh` runs `qemu-img convert -c` so dead/bloated clusters are
dropped (this is what shrank `download-vm-xps` from 238 GB to ~8.5 GB).
`metadata.yaml` is written once per VM so the fingerprint is stable; changing it
would make OpenTofu plan a replacement.

## Troubleshooting

- **Won't boot**: images are UEFI systemd-boot with `security.secureboot = "false"`
  (in the `vm-base` profile). Check `incus console --show-log <vm>`.
- **No network**: guest should use `eth0` (`net.ifnames=0`); NIC must bridge to
  `br0` (`incus config show <vm>`).
- **`incus exec` fails**: guest needs `virtualisation.incus.agent.enable = true`
  and a running `incus-agent`; rebuild with `nup-fleet`.
- **`incusd` segfaults / client websocket 1006 on a big VM**: the daemon's
  embedded raft/cowsql DB is fragile on huge disk copies. Compact the source image
  so the copy is small; run mainline `pkgs.incus` (set in
  `virtualization-incus.nix`).
- **Root fills on `xps17`**: `incus config get storage.images_volume` must be
  `local/incus-images` and `/var/lib/incus/images` must be empty.
- **Disk keeps growing**: TRIM isn't reaching the host — see [TRIM / qcow2 size](#trim--qcow2-size).
- **`tofu apply` wants to replace a VM**: the image fingerprint changed;
  `prevent_destroy` blocks the destroy. Fix the staging metadata, don't force it.