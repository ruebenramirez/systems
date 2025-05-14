
{ config, pkgs, ... }:

let

in
{
  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user="rramirez";
  };

  environment.systemPackages = with pkgs; [
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
  ];
}
