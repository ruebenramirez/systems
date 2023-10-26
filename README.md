# systems


# update this flake

to update the flake.lock to the current release of nix packages

```
nix flake update
```

Afterwards re-run the flake

```
sudo nixos-rebuild switch --flake ~/systems-repo-location#MachineName
