{ config, pkgs, ... }:

{

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      mesa
      libva
      libva-utils
    ];
  };

  environment.variables = {
    LIBVA_DRIVER_NAME = "radeonsi";
  };

}
