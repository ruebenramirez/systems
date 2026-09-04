{ pkgs, ... }:

let
  pine = pkgs.callPackage ../../pkgs/pine/package.nix { };
in
{
  environment.systemPackages = [ pine ];
}
