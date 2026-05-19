{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
      k3d # k3s on docker (docker required)
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

  # k3d requires docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    extraOptions = "--iptables=true --ip-masq=true --ip-forward=true";
  };

  # Disable automatic start of Docker service
  #systemd.services.docker.wantedBy = pkgs.lib.mkForce [];

  # Ensure the service is not masked
  systemd.services.docker.unitConfig.AssertPathExists = "/run/booted-system";


}
