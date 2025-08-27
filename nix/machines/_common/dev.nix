{ config, pkgs, ... }:

let

in
{
  environment.systemPackages = with pkgs; [
    harlequin # SQL TUI
    hugo
  ];
}
