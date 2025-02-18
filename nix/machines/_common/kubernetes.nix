
{ config, pkgs, ... }:

let

in
{


  virtualisation.docker = {
    enable = true; # required for k3d
    enableOnBoot = true;
    extraOptions = "--iptables=true --ip-masq=true --ip-forward=true";
  };
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
