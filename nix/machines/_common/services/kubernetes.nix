{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

  # Docker, not Kubernetes: k3d is gone and the Forgejo Actions runner now talks
  # to Podman, so `dev-vm-xps` is the only host left that wants a docker daemon.
  # Everyone else switches it off themselves (homeserver: srv/podman-only.nix,
  # forgejo-ci-runner-vm: services/podman.nix).
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    extraOptions = "--iptables=true --ip-masq=true --ip-forward=true";
  };

  # Ensure the service is not masked
  systemd.services.docker.unitConfig.AssertPathExists = "/run/booted-system";
}
