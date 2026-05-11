{ config, pkgs, ... }:

{
  # Enable the OpenRazer daemon
  hardware.openrazer = {
    enable = true;
    users = [ "rramirez" ];
  };

  environment.systemPackages = with pkgs; [
    # GUI and CLI tool for managing Razer devices
    polychromatic

    # Python library for OpenRazer (if you wish to script it manually)
    python311Packages.openrazer
  ];
}
