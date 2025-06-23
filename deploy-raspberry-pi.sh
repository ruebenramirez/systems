#!/usr/bin/env bash

nix flake update

# update pi
NIX_SSHOPTS="-o RequestTTY=force" nixos-rebuild switch \
    --flake '.#raspberry-pi' \
    --target-host nixos@100.106.37.128 \
    --use-remote-sudo
