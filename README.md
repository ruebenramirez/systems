## Acknowledgments

A special thanks to [`@sarcasticadmin`](https://github.com/sarcasticadmin) for
pointing me down the Nix road. Rob's [flake
example](https://github.com/sarcasticadmin/systems) of Nix possibilities became
the foundation for managing all of my machines declaratively.

**This is the way.**

# systems

A single NixOS flake defining 11 machines:
- 7 physical boxes: laptops, servers, a VPS, and a Raspberry Pi
- 4 QEMU VMs deployed to `xps17`.

![Quarterly system flake commit volume and machine additions](docs/system-flake-commit-volume.svg)

## Fleet Architecture

- **Shared modules.** Per-machine config lives in `nix/machines/<name>/`;
  reusable modules (base packages, sway desktop, dev tooling, VPN clients,
  build-machine, …) live in `nix/machines/_common/` and are composed per
  machine.
- **Secrets.** Encrypted secrets live in a dedicated private repository
  imported as the `systems-secrets` flake input; `sops-nix` decrypts them on
  each machine.
- **Networking.** `wgnet` is a WireGuard service network spanning the home
  network, providing remote access from the daily-driver laptop and connecting
  a VPS that exposes inbound SMTP.
- **VMs.** [disko](https://github.com/nix-community/disko) defines disk
  layouts; `scripts/build-and-deploy-vm.sh` builds qcow2 images and deploys
  them with libvirt using Nix-defined memory, vCPUs, and networking.
- **Cross-building.** `fwai0` and `xps17` import `build-machine.nix`, which
  enables aarch64 binfmt emulation and tuning for slow ARM builds — used to
  build the `pi-syncoid-target` SD image
  (`scripts/build-raspberrypi-image.sh`) and VM images from the builder.

## nup-fleet

[`nup-fleet`](dotfiles/bin/nup-fleet) builds on the builder and applies
configurations to the fleet over SSH.

### Usage

```bash
nup-fleet                # rebuild + switch every machine in the list
nup-fleet driver         # one machine, by flake config name
nup-fleet build          # build all configs locally only (no deploy)
nup-fleet --upgrade       # run `nix flake update` first, then deploy all
nup-fleet --upgrade xps17  # flake update + single machine
```

### Machines

| Machine | Role | config/services |
|---------|------|-----------------|
| `dev-vm-xps` | Dev VM | Docker, [k3d](https://github.com/k3d-io/k3d), Go, Python, Rust, [Hugo](https://github.com/gohugoio/hugo) |
| `driver` | daily driver thin client | [Sway](https://github.com/swaywm/sway), [Mullvad](https://mullvad.net), `wgnet` |
| `forgejo-ci-runner-vm` | Forgejo runner | [Forgejo Runner](https://code.forgejo.org/forgejo/runner) via Docker |
| `fwai0` | Fleet builder and LLM inference server | Vulkan-backed [`llama.cpp`](https://github.com/ggml-org/llama.cpp) serving [`Qwen3.8-27B-MTP`](https://huggingface.co/unsloth/Qwen3.8-27B-GGUF) and [`Qwen3.6-35B-A3B-MTP`](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF) over `wgnet` |
| `homeserver` | App, file, and mail server | [Stalwart](https://github.com/stalwartlabs/stalwart), [Gmail sync](https://github.com/imapsync/imapsync), [Jellyfin](https://github.com/jellyfin/jellyfin), [Immich](https://github.com/immich-app/immich), [Audiobookshelf](https://github.com/advplyr/audiobookshelf), [FreshRSS](https://github.com/FreshRSS/FreshRSS), [SearXNG](https://github.com/searxng/searxng), [Open WebUI](https://github.com/open-webui/open-webui) |
| `pi-syncoid-target` | ZFS replication target | Hourly [`syncoid`](https://github.com/jimsalterjrs/sanoid) snapshot replication of `homeserver`'s `tank/data` dataset |
| `ssdnodes-1` | Public MX relay and web host | [Postfix](https://github.com/vdukhovni/postfix) relay to [Stalwart](https://github.com/stalwartlabs/stalwart) over `wgnet`, nginx reverse proxy, containerized [WordPress](https://hub.docker.com/_/wordpress/) sites |
| `xps17` | Libvirt VM host | [libvirt](https://github.com/libvirt/libvirt)/KVM, `devpool` VM storage, Docker, [k3d](https://github.com/k3d-io/k3d), ARM64 builds |

## Docs

- [NixOS ZFS install](docs/nixos-zfs-install.md)
- [System flake activity chart](docs/system-flake-activity.md)
