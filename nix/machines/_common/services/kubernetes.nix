{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

  # Tooling only. This used to turn on a docker daemon for every host that
  # imports it -- k3d needed one, and so did the Forgejo Actions runner. Both are
  # gone: the runner speaks to Podman (forgejo-ci-runner-vm: services/podman.nix)
  # and no host in the fleet runs a docker daemon.
}
