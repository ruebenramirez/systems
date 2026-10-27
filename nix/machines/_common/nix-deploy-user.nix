{ config, lib, pkgs, ... }:
# `nixdeploy`: the key-only deploy account CI uses. `nup-fleet --upgrade` runs
# `nix copy --to ssh://nixdeploy@<host>` (hence trusted-user) and
# `sudo ... switch-to-configuration switch` (hence NOPASSWD ALL -- the sudo
# wrapper is an arbitrary /bin/sh, so it cannot be narrowed). Never a human
# account: rotating a CI key must not lock anyone out.
#
# BLAST RADIUS: imported by every machine, so this key is root on all of them.
# Anything needing narrower access wants its own account -- see
# `nix/machines/fwai0/services/nix-builder-access.nix` and docs/fleet-keys.md.
let
  # Public half; the private half is the sops secret forgejo_runner_ssh_key.
  # Rotate both together.
  deployPubKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMOcbCRgikgRO4GYHrt6o7bBl+TYjtXm8FfQ8dIM/MSh forgejo-ci-runner-vm fleet deploy key";
in
{
  users.users.nixdeploy = {
    isSystemUser = true;
    group = "nixdeploy";
    # Reached only via `ssh <cmd>`.
    shell = pkgs.bashNonInteractive;
    home = "/var/lib/nixdeploy";
    createHome = true;
    openssh.authorizedKeys.keys = [ deployPubKey ];
  };

  users.groups.nixdeploy = { };

  # lets `nix copy` import unsigned closures
  nix.settings.trusted-users = [ "nixdeploy" ];

  security.sudo.extraRules = [{
    users = [ "nixdeploy" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];
}
