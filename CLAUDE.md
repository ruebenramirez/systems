# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a NixOS declarative systems management repository using Nix flakes. It manages 11 machines including desktops, servers, VMs, and a Raspberry Pi with a modular configuration approach.

## Common Commands

```shell
# Update flake.lock to latest nixpkgs
nix flake update

# Rebuild and switch to new configuration
sudo nixos-rebuild switch --flake ~/code/systems#MachineName

# Build a VM image (qcow2)
nix build .#packages.x86_64-linux.VMNAME

# Test configuration without switching
sudo nixos-rebuild test --flake ~/code/systems#MachineName

# Build without activating
sudo nixos-rebuild build --flake ~/code/systems#MachineName
```

Machine names: `xps17`, `driver`, `x220`, `homeserver`, `ssdnodes-1`, `pi-syncoid-target`, `fwai0`, `dev-vm-xps`, `download-vm-xps`, `openclaw-vm`

## Architecture

### Flake Structure (`flake.nix`)
- **Inputs**: nixpkgs (25.11), nixpkgs-unstable, disko, nixos-generators, nixos-hardware
- **Outputs**: nixosConfigurations for each machine, packages for VM images
- **Multi-arch**: x86_64-linux, aarch64-linux, armv7l-linux, armv6l-linux

### Directory Layout

```
nix/
  machines/
    _common/           # Shared reusable modules
      base/            # Core tools, editor, gpg, tmux, yubikey
      desktop/         # Wayland/Sway, terminals, desktop apps
      homeserver/srv/  # Homelab services (jellyfin, immich, freshrss, etc.)
      services/        # kubernetes, virtualization, wireguard, syncthing
      *.nix            # Role modules (dev, gaming, gpu-nvidia, gpu-amd, etc.)
    [machine-name]/    # Per-machine configuration
      default.nix      # Machine entry point (imports modules)
      hardware-configuration.nix

dotfiles/              # User dotfiles symlinked via generic-linker
  .config/             # fish, sway, alacritty, wezterm, mako
  bin/                 # Utility scripts (volume, brightness, sync)

scripts/               # System bootstrap and deployment scripts
overlays/              # Custom package overlays
```

### Key Patterns

**Module Composition**: Each machine's `default.nix` imports only needed modules from `_common/`:
```nix
imports = [
  ../_common/base
  ../_common/desktop
  ../_common/dev.nix
  ../_common/services/kubernetes.nix
];
```

**Generic Linker** (`nix/lib/generic-linker.nix`): Uses systemd tmpfiles to symlink dotfiles from this repo to user home directories.

**ZFS Persistence**: Machines use ephemeral root with persistent `/persist` directory for SSH keys, caches, and stateful data.

**Unstable Packages**: Access via `pkgs.unstable.packageName` after importing the overlay in machine config.

### Service Modules

Services are defined in `nix/machines/_common/` and conditionally imported:
- `services/kubernetes.nix` - Docker + k3d (disabled by default, manual start)
- `services/wireguard-server.nix` - VPN server
- `services/syncthing-*.nix` - File sync variants
- `homeserver/srv/*.nix` - Jellyfin, Immich, FreshRSS, PostgreSQL, Redis, etc.

### Hardware Abstractions

- GPU support: `gpu-nvidia.nix` (CUDA), `gpu-amd.nix` (ROCm)
- Virtualization: `virtualization-intel.nix`, `virtualization-amd.nix`
- Hardware-specific: fingerprint readers, YubiKey, custom keyboard mappings
