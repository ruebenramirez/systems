{ ... }:

{
  imports = [ ../../_common/container-mirrors.nix ];

  # homeserver runs podman and nothing else.
  virtualisation.podman.enable = true;

  # Its two containers are built into the closure (pull = "never"), so this only
  # covers manual `podman pull` here -- but it costs nothing to be consistent.
  my.containerMirrors.enable = true;
}
