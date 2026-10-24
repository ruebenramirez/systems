{ config, pkgs, lib, ... }:
# Build only on fwai0; never compile locally.
#
# dev-vm-xps is a development VM, not a builder. All Nix builds must be
# offloaded to fwai0 over SSH, and local compilation is disabled outright so a
# stray `nix build` fails loudly instead of saturating the VM's (shared) CPUs.
#
# Mechanism:
#   * `nix.buildMachines` registers fwai0 as the one remote builder. Nix drives
#     it as the daemon (root), so root needs the key below. We reuse the
#     existing dedicated `nixdeploy` deploy key rather than the human's key:
#     its public half is already trusted fleet-wide via
#     `_common/nix-deploy-user.nix`, and fwai0 forbids root SSH login, so we
#     connect as `nixdeploy`.
#   * `nix.settings.max-jobs = 0` means "no local build jobs". Combined with the
#     remote builder, builds offload to fwai0; if fwai0 is unreachable the build
#     fails rather than falling back to local compilation.
#   * `protocol = "ssh-ng"` (the modern store protocol) avoids the legacy
#     `nix-store --serve` mismatch that breaks `nixos-rebuild --build-host`
#     against newer Nix.
let
  # fwai0's SSH host key (ed25519), pinned so the root-run daemon verifies the
  # builder without an interactive prompt. Rotate if fwai0's host key changes.
  fwai0HostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFfWwOJidKiVGkSL5/ejyCqYc6LbhWw1txtpa0a33h/J";
in
{
  # Private half of the fleet deploy key, owner=root so the Nix daemon can read
  # it. The matching public key is trusted on every host via
  # `_common/nix-deploy-user.nix`.
  sops.secrets.forgejo_runner_ssh_key = {
    owner = "root";
    group = "root";
    mode = "0400";
  };

  # Pin fwai0's host key in the global known_hosts, which both the root-run
  # daemon and normal users read.
  programs.ssh.knownHosts.fwai0 = {
    hostNames = [ "fwai0" "fwai0.tailnet.rueb.dev" "fwai0.homenet.rueb.dev" ];
    publicKey = fwai0HostKey;
  };

  nix.distributedBuilds = true;

  nix.buildMachines = [
    {
      hostName = "fwai0";
      # fwai0 sets PermitRootLogin=no; connect as the dedicated deploy user.
      sshUser = "nixdeploy";
      sshKey = config.sops.secrets.forgejo_runner_ssh_key.path;
      protocol = "ssh-ng";
      systems = [ "x86_64-linux" "aarch64-linux" ];
      maxJobs = 32;
      supportedFeatures = [ "benchmark" "big-parallel" "kvm" "nixos-test" ];
    }
  ];

  nix.settings = {
    # No local build jobs: everything goes to fwai0.
    max-jobs = 0;
    # Let the builder fetch prebuilt paths from substituters instead of
    # rebuilding them.
    builders-use-substitutes = true;
  };
}
