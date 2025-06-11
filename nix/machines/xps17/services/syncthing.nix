
{ config, pkgs, ... }:
let
  # Locals
in
{

  # install syncthing packages
  environment.systemPackages = with pkgs; [
    syncthing
    syncthingtray
  ];

  # enable and configure the syncthing service
  services = {
      syncthing = {
          enable = true;
          guiAddress = "0.0.0.0:8384";
          user = "rramirez";
          dataDir = "/home/rramirez/Sync";    # Default folder for new synced folders
          configDir = "/home/rramirez/.config/syncthing";   # Folder for Syncthing's settings and keys
      };
  };
}
