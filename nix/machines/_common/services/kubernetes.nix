{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

  # Client tooling only: nothing here runs a cluster or a container engine. The
  # runner's own engine lives in forgejo-ci-runner-vm: services/podman.nix.
}
