{ config, pkgs, lib, ... }:
# Give the Forgejo CI runner everything it needs to run
# `nup-fleet --upgrade` against the whole fleet from host-mode jobs.
#
# Design:
#   * Host-mode ("nixos" label) jobs execute as the dedicated `nixdeploy`
#     user (see `_common/nix-deploy-user.nix`), which every fleet machine
#     trusts for SSH + sudo. Docker jobs are unaffected.
#   * `nixdeploy` on this VM holds the private half of the fleet deploy key
#     (sops secret `forgejo_runner_ssh_key`); the public half is baked into
#     `_common/nix-deploy-user.nix` and trusted everywhere.
#   * `~/.ssh/config` maps each fleet name to its Tailscale MagicDNS FQDN,
#     so `nup-fleet`'s bare `ssh <name>` calls resolve deterministically
#     without depending on resolver search-domain behavior.
let
  fleetHosts = [
    "xps17"
    "dev-vm-xps"
    "fwai0"
    "homeserver"
    "driver"
    "ssdnodes-1"
    "download-vm-xps"
    "forgejo-ci-runner-vm"
    "hermes-vm-xps"
    "pi-syncoid-target"
  ];

  # Tailscale MagicDNS suffix for the self-hosted headscale (hs.rueb.dev).
  magicDnsSuffix = "tailnet.rueb.dev";

  deployUser = "nixdeploy";

  fleetSshConfig = lib.concatMapStrings (host: ''
    Host ${host}
      HostName ${host}.${magicDnsSuffix}
      User ${deployUser}
      IdentityFile ${config.sops.secrets.forgejo_runner_ssh_key.path}
      IdentitiesOnly yes
      StrictHostKeyChecking accept-new
  '') fleetHosts;
in
{
  # Private half of the fleet deploy key used by host-mode CI jobs. The
  # matching public key is trusted by every machine via
  # `_common/nix-deploy-user.nix`.
  sops.secrets.forgejo_runner_ssh_key = {
    owner = deployUser;
    group = "nixdeploy";
    mode = "0400";
  };

  # `_common/base/ssh.nix` already sets the keepalive defaults; this only
  # adds the per-fleet host mappings.
  programs.ssh.extraConfig = fleetSshConfig;
}
