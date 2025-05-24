
# The base toolchain that I expect on a system
{ config, pkgs, pkgs-unstable, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    mosh
  ];

  programs.mosh = {
    enable = true;
    openFirewall = true;
  };
}
