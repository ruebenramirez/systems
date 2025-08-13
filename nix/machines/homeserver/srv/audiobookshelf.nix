{ config, pkgs, pkgs-unstable, ... }:

let

in
{
  services.audiobookshelf = {
    enable = true;
    host = "0.0.0.0";
    port = 13378;
    openFirewall = true;
    package = pkgs-unstable.audiobookshelf;
    user = "rramirez";
  };
}
