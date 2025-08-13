{ config, pkgs, ... }:

{
  services = {
      syncthing = {
          enable = true;
          guiAddress = "0.0.0.0:8384";
          user = "rramirez";
          dataDir = "/home/rramirez/Sync";
          configDir = "/home/rramirez/.config/syncthing";
      };
  };
}
