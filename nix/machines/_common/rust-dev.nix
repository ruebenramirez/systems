{ config, pkgs, ... }:

let

in
{
  environment.systemPackages = with pkgs; [

    # rust development
    cargo
    gcc
    rustc
    rustfmt
    #rustup
  ];
}
