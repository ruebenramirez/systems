
{ config, pkgs, ... }:

let

in
{


  virtualisation.docker = {
    enable = true; # required for k3d
    enableOnBoot = true;
    extraOptions = "--iptables=true --ip-masq=true --ip-forward=true";
  };

  # disable docker systemd service by default (must start prior to using docker)
  # systemd.services.docker.enable = false; # masks the service (doesn't allow manual starts)
  # Disable automatic start of Docker service
  systemd.services.docker.wantedBy = pkgs.lib.mkForce [];

  # Ensure the service is not masked
  systemd.services.docker.unitConfig.AssertPathExists = "/run/booted-system";

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
  networking.firewall.trustedInterfaces = [ "docker0" ];

  environment.systemPackages = with pkgs; [
      k3d # k3s on docker (docker required)
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

}
