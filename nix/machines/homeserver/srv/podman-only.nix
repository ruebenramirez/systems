{ ... }:

{
  # homeserver runs podman and nothing else -- forgejo and the Actions runner
  # used to live on a docker daemon here, and this is where that daemon went away.
  virtualisation.podman.enable = true;
}
