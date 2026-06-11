# systems

## Docs

- [NixOS ZFS install](docs/nixos-zfs-install.md)


# update this flake

to update the flake.lock to the current release of nix packages

```shell
nix flake update
```

Afterwards re-run the flake

```shell
sudo nixos-rebuild switch --flake ~/systems-repo-location#MachineName
```
