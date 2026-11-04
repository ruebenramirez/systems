{ config, lib, ... }:

{
  # homeserver runs podman and nothing else.
  #
  # `_common/services/kubernetes.nix` turns docker on for the whole fleet, and
  # docker is where forgejo and the Actions runner used to live.
  # Overridden here rather than in the shared module because `dev-vm-xps` still
  # wants a docker daemon -- it is the only one left.
  virtualisation.docker = {
    enable = lib.mkForce false;
    enableOnBoot = lib.mkForce false;
  };

  # kubernetes.nix sets a unitConfig on docker.service unconditionally, which
  # leaves an enabled stub unit behind once the package is gone.
  systemd.services.docker.enable = lib.mkForce false;

  virtualisation.podman.enable = true;
}
