{ config, lib, ... }:

{
  # homeserver runs podman and nothing else.
  #
  # `_common/services/kubernetes.nix` turns docker on for k3d, which this machine
  # does not use, and docker is where forgejo and the Actions runner used to live.
  # Overridden here rather than in the shared module because `ssdnodes-1`,
  # `forgejo-ci-runner-vm` and `dev-vm-xps` all still need a docker daemon.
  virtualisation.docker = {
    enable = lib.mkForce false;
    enableOnBoot = lib.mkForce false;
  };

  # kubernetes.nix sets a unitConfig on docker.service unconditionally, which
  # leaves an enabled stub unit behind once the package is gone.
  systemd.services.docker.enable = lib.mkForce false;

  virtualisation.podman.enable = true;
}
