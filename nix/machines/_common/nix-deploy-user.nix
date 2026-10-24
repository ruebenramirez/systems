{ config, lib, pkgs, ... }:
# Dedicated user for automated fleet builds and deployments.
#
# `nup-fleet --upgrade` runs from a Forgejo CI host-mode job and then, for
# every machine, does:
#   * `nix copy --to ssh://nixdeploy@<host>` to push the built closure
#     (requires the account to be a nix `trusted-user` to import it), and
#   * `ssh nixdeploy@<host> sudo ... switch-to-configuration switch`
#     to activate it.
#
# This is deliberately *not* `rramirez`: CI should not hold an interactive
# human's credentials, and a CI key rotation should not be able to lock the
# human out. The account is key-only (no password), has no interactive
# shell, and exists purely for deployment.
#
# Sudo scope: `nixos-rebuild --sudo` executes
#   `sudo /bin/sh -c '<script> systemd-run <config>/bin/switch-to-configuration switch'`
# on the target. Because the wrapper is an arbitrary `/bin/sh`, sudo cannot
# be narrowed to a specific command without breaking activation, so the
# account gets NOPASSWD for ALL. The privilege boundary is therefore the SSH
# key, which lives only on the CI runner host as a sops secret.
#
# BLAST RADIUS: this module is imported by every machine in the fleet, so the
# key below is trusted-user + NOPASSWD-root on all of them. Treat
# `forgejo_runner_ssh_key` as the single most sensitive credential in the
# system. Anything that needs SSH to a host for a *narrower* purpose must get a
# narrower account instead of reusing this key -- see
# `nix/machines/fwai0/services/nix-builder-access.nix` for the pattern, and
# `docs/fleet-keys.md` for the inventory and rotation procedure.
let
  # Public half of the CI deploy key. The private half is the sops secret
  # `forgejo_runner_ssh_key`, decrypted only on forgejo-ci-runner-vm.
  # Rotate by regenerating the key pair and updating both places.
  deployPubKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBt6TezkfAd+VA2N0dkNKnw50xM4YKNOpEVqdc8s7WpY forgejo-ci-runner-vm fleet deploy key";
in
{
  users.users.nixdeploy = {
    isSystemUser = true;
    group = "nixdeploy";
    # No usable login shell: the account is reached only via `ssh <cmd>`.
    shell = pkgs.bashNonInteractive;
    home = "/var/lib/nixdeploy";
    createHome = true;
    openssh.authorizedKeys.keys = [ deployPubKey ];
  };

  users.groups.nixdeploy = { };

  # Required so `nix copy --to ssh://nixdeploy@<host>` may import closures
  # into the store without a signature.
  nix.settings.trusted-users = [ "nixdeploy" ];

  security.sudo.extraRules = [{
    users = [ "nixdeploy" ];
    commands = [{
      command = "ALL";
      options = [ "NOPASSWD" ];
    }];
  }];
}
