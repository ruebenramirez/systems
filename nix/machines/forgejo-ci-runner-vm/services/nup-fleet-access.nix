{ config, pkgs, lib, tailnet, ... }:
# What the CI runner needs to run `nup-fleet --upgrade` from host-mode jobs:
# the fleet deploy key, a read token for the private systems-secrets repo, and
# ssh mappings from fleet names to MagicDNS FQDNs so bare `ssh <name>` calls
# resolve without search-domain help.
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
  # private half; the public half every machine trusts lives in
  # _common/nix-deploy-user.nix
  sops.secrets.forgejo_runner_ssh_key = {
    owner = deployUser;
    group = "nixdeploy";
    mode = "0400";
  };

  # read-only Forgejo token for the private systems-secrets repo
  sops.secrets.forgejo_secrets_token = {
    owner = deployUser;
    group = "nixdeploy";
    mode = "0400";
  };

  # Rendered by sops-nix so the token never lands in the world-readable store.
  # Values must stay unquoted: libcurl does not strip quotes.
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

  # nix's own libcurl fetcher reads netrc-file, not ~/.netrc
  nix.settings.netrc-file = config.sops.templates."nixdeploy-netrc".path;

  # git -- and nix's git subprocesses -- read ~/.netrc; 0400 or curl refuses it
  systemd.tmpfiles.rules = [
    "d /var/lib/nixdeploy 0700 nixdeploy nixdeploy -"
    "L+ /var/lib/nixdeploy/.netrc - - - - ${config.sops.templates."nixdeploy-netrc".path}"
  ];

  programs.ssh.extraConfig = fleetSshConfig;
}
