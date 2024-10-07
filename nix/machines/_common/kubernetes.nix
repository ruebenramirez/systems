
{ config, pkgs, ... }:

let

in
{


  virtualisation.docker.enable = true; # required for k3d

  environment.systemPackages = with pkgs; [
      k3d # k3s on docker (docker required)
      kubectl
      kubernetes-helm
      helmfile-wrapped
  ];

}
