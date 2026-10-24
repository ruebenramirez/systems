{ config, lib, pkgs, ... }:
# Narrow, unprivileged remote-builder access for fwai0.
#
# fwai0 is the fleet's compile farm. Until now the only account that could
# offload builds to it was `nixdeploy` -- the fleet-wide CI deploy identity,
# which is a nix trusted-user *and* has NOPASSWD sudo on all ten machines. That
# made every remote build depend on a credential with fleet-root blast radius:
# a leak of the CI key, or of this key reused as a builder key, was root on
# everything.
#
# `nixbuilder` exists to shrink that. It can do exactly one thing: accept
# `nix store build` work over ssh-ng.
#   * trusted-user: required so the Nix daemon will accept unsigned .drv
#     outputs imported over the wire (this is what makes remote builds work).
#   * NOT a sudoer: it cannot activate configurations, read other users'
#     files, or touch the system.
#   * bashNonInteractive: no interactive login, only `ssh <host> <cmd>`.
#   * key-only, and the key is used for nothing else in the fleet.
#
# The private half of this key is the sops secret `fwai0_builder_ssh_key`,
# decrypted only on dev-vm-xps (the build client). Rotate by regenerating the
# pair, updating this public key and that secret, and redeploying fwai0 then
# dev-vm-xps.
let
  builderPubKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA07JmgY4C++rhodbHaZLGQjBnY+yqnpbNHP6qAHHAXT fwai0-nixbuilder@20261024";
in
{
  users.users.nixbuilder = {
    isSystemUser = true;
    group = "nixbuilder";
    shell = pkgs.bashNonInteractive;
    home = "/var/lib/nixbuilder";
    createHome = true;
    openssh.authorizedKeys.keys = [ builderPubKey ];
  };

  users.groups.nixbuilder = { };

  # Lets the Nix daemon accept build results imported by this account, which is
  # what `ssh-ng://nixbuilder@host` requires. Deliberately the *only* privilege
  # granted.
  nix.settings.trusted-users = [ "nixbuilder" ];
}
