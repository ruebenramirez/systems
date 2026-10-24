{ config, pkgs, lib, tailnet, ... }:
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

  # The MagicDNS suffix comes from the shared tailnet constant
  # (nix/lib/tailnet.nix), which is also headscale's own base_domain.
  deployUser = "nixdeploy";

  fleetSshConfig = lib.concatMapStrings (host: ''
    Host ${host}
      HostName ${host}.${tailnet.domain}
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

  # Read-only Forgejo access token for the private `systems-secrets` repo.
  # `nix flake update` (and any flake evaluation) must fetch that input, and
  # the repo requires auth. Nix reads credentials from its `netrc-file`
  # setting (not the user's ~/.netrc), so point that at the rendered netrc
  # below; plain git also uses ~/.netrc.
  sops.secrets.forgejo_secrets_token = {
    owner = deployUser;
    group = "nixdeploy";
    mode = "0400";
  };

  # Netrc for the Forgejo host, rendered by sops-nix so the token never
  # lands in the world-readable store. `machine` matches the git host;
  # `login`/`password` carry the token.
  #
  # Note: netrc values must be unquoted; libcurl's parser does not strip
  # quotes, so a quoted token would be sent verbatim with the quotes.
  sops.templates."nixdeploy-netrc" = {
    content = ''
      machine code.rueb.dev
        login ${config.sops.placeholder.forgejo_secrets_token}
        password ${config.sops.placeholder.forgejo_secrets_token}
    '';
    owner = deployUser;
    group = "nixdeploy";
    mode = "0400";
    restartUnits = [ "forgejo-ci-runner.service" ];
  };

  # Nix's git fetcher uses `netrc-file` (default /etc/nix/netrc), not
  # ~/.netrc, so point it at the rendered netrc.
  nix.settings.netrc-file = config.sops.templates."nixdeploy-netrc".path;

  # Plain `git` invoked by jobs (and by nix flake update's sub-processes)
  # reads ~/.netrc. .netrc must not be group/world readable or curl refuses
  # it, hence mode 0400 on the template.
  systemd.tmpfiles.rules = [
    "d /var/lib/nixdeploy 0700 nixdeploy nixdeploy -"
    "L+ /var/lib/nixdeploy/.netrc - - - - ${config.sops.templates."nixdeploy-netrc".path}"
  ];

  # `_common/base/ssh.nix` already sets the keepalive defaults; this only
  # adds the per-fleet host mappings.
  programs.ssh.extraConfig = fleetSshConfig;
}
