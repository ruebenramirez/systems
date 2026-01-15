{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    (btop.override { rocmSupport = true; })
    nvtopPackages.amd
    vulkan-tools
    vulkan-loader
    vulkan-validation-layers
  ];


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
