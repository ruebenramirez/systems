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

Guests also join the tailnet, so `ssh <vm>` works from anywhere (e.g.
`ssh dev-vm-xps`), alongside `incus exec`.

## Updating a guest

The VM image is just the seed; day-to-day changes (packages, services, apps) are
normal NixOS rebuilds inside the guest:

```sh
nup-fleet --upgrade dev-vm-xps   # flake update + rebuild
nup-fleet dev-vm-xps             # rebuild only
```

`nup-fleet` uses `ssh <name>` (the tailnet) and works for all three guests.

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

## Create a new VM

Adding a VM touches three places: the NixOS guest (which builds the disk image),
OpenTofu (the instance and its resources), and the fleet (`nup-fleet`).

**Name invariant:** the name must be identical in `networking.hostName`, the
`nixosConfigurations.<vm>` key, the `tofu/locals.tf` `vms` key, the `nup-fleet`
`MACHINES` entry, and the Incus instance name. Pick it once and reuse it.

### 1. Guest config

Create `nix/machines/<vm>/configuration.nix`. Minimal example:

```nix
{ config, lib, pkgs, ... }:
{
  imports = [
    ../_common/base/default.nix
    ../_common/qemu-vm-guest.nix        # net.ifnames=0 -> eth0, incus-agent
    # ../_common/tailscale-client.nix   # optional
    # ../_common/vm-nfs-client.nix      # optional (tank data)
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.growPartition = true;

  disko.memSize = 4096;
  disko.imageBuilder.imageFormat = "qcow2";
  disko.devices.disk.main = {
    device = "/dev/vda";
    imageName = "<vm>";
    imageSize = "100G";                 # provisioned disk size
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "512M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; };
        };
      };
    };
  };

  networking.hostName = "<vm>";

  users.users.rramirez = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... me" ];
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "25.11";
}
```

The disk **size** comes from `disko...imageSize` and is baked into the image, so
there's nothing to set in OpenTofu.

### 2. flake.nix

Add a `nixosConfigurations.<vm>` entry (mirror an existing guest) and a
`packages."x86_64-linux".<vm>-incus-image` entry:

```nix
"<vm>" = nixpkgs.lib.nixosSystem {
  modules = [
    ./nix/machines/<vm>/configuration.nix
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    nixpkgs.nixosModules.readOnlyPkgs
    {
      nixpkgs.pkgs = nixpkgsFor."x86_64-linux";
      _module.args = {
        pkgs-unstable = unstableFor."x86_64-linux";
        inherit systems-secrets;
      };
    }
  ];
};
```
```nix
# inside packages."x86_64-linux"
"<vm>-incus-image" = mkIncusImage self.nixosConfigurations."<vm>";
```

### 3. nup-fleet

Add `"<vm>"` to `MACHINES` in [`dotfiles/bin/nup-fleet`](../dotfiles/bin/nup-fleet).

### 4. Build and stage the image

```sh
nix build .#<vm>-incus-image              # unified image tar (metadata.yaml + rootfs.img)
tofu/scripts/build-incus-image.sh <vm>    # stages /devpool/incus-migration/<vm>.tar
```

`nix/lib/mk-incus-image.nix` wraps disko's qcow2 with `qemu-img convert -c` (drops
dead clusters) and a fixed `metadata.yaml` `creation_date` (stable fingerprint).

### 5. tofu/locals.tf

Add a `vms` entry:

```hcl
"<vm>" = {
  vcpus     = 4
  memory    = "4096MiB"
  mac       = "52:54:00:aa:bb:cc"
  image_dir = "${local.stage}/<vm>.tar"
};
```

### 6. Register, create, adopt

```sh
tofu/scripts/create-vm.sh <vm>
```

which runs `tofu apply -target='incus_image.vm["<vm>"]'` → `incus init local:$fp <vm> --vm -p vm-base`
→ set limits → add `eth0` (bridged `br0`, `hwaddr`) → `incus start` → `tofu import` → `tofu plan`.

Instances are created with the **Incus CLI and imported**, not created by the
provider: the `lxc/incus` provider's create path drops the websocket / segfaults
`incusd` on large disk copies, and the CLI can't create a VM without a profile —
hence the `vm-base` profile (root disk + `secureboot=false` + `autostart`).

### 7. Secrets / bootstrap

- **sops** (`systems-secrets`): add the host's age key (derived from its SSH host
  key once it first boots), or reuse the shared `tailscale-auth-key`.
- **tailscale**: importing `tailscale-client.nix` needs `sops.secrets.tailscale-auth-key`.
- **NFS**: if it needs tank data, add `my.vmNfsServer.shares."<vm>" = [ "data" ]`
  on `homeserver` and `my.vmNfsClient.mounts.data = { }` in the guest, then
  `nup-fleet --upgrade homeserver` and `nup-fleet --upgrade <vm>`.

### 8. Verify

```sh
incus list <vm>
incus exec <vm> -- ip -br addr     # eth0 + LAN IP
ssh <vm>                            # tailnet
nup-fleet --upgrade <vm>
```
Then add the `Host <vm>-lan` SSH snippet.

## Removing a VM

```sh
cd ~/code/systems/tofu
tofu state rm 'incus_instance.vm["<vm>"]' 'incus_image.vm["<vm>"]'
incus delete <vm> --force
incus image delete <fingerprint>
```

then drop it from `tofu/locals.tf`, `flake.nix` (both `nixosConfigurations` and the
`packages` image entry), and `nup-fleet` `MACHINES`.

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
- **Tailnet/exit-node traffic goes nowhere on `download-vm-xps`**: its Mullvad
  `wg-quick` tunnel installs a default route in table 51820 via a rule (priority
  5209) that precedes Tailscale's `lookup 52` rule (5270), hijacking
  `100.64.0.0/10` and `fd7a:115c:a1e0::/48` (breaks tailnet SSH and exit-node
  return traffic). `mullvad-vpn-client.nix` adds a `tailnet-route-fix` oneshot
  that pins both ranges to table 52 at priority 5200. Check with
  `ip route get 100.64.0.1` (expect `dev tailscale0`).
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