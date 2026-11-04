{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

  # Docker, not Kubernetes: what still needs a container engine is the Forgejo
  # Actions runner on forgejo-ci-runner-vm. Hosts that have moved to Podman
  # have to switch it off themselves (homeserver: srv/podman-only.nix).
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    extraOptions = "--iptables=true --ip-masq=true --ip-forward=true";
  };

  # Ensure the service is not masked
  systemd.services.docker.unitConfig.AssertPathExists = "/run/booted-system";
}
