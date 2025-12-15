
# This config is only to contain shared desktop configuration
{ config, pkgs, betterbird-stable, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    android-tools
    android-studio
    android-studio-tools
    android-file-transfer
  ];

  programs.adb.enable = true;
}
