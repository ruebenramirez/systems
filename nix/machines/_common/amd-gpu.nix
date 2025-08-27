{ config, pkgs, ... }:

{

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      mesa
      libva
      libva-utils
      rocmPackages.clr.icd
    ];
  };

  environment.systemPackages = with pkgs; [
    btop-rocm
    clinfo
    nvtopPackages.amd
    rocmPackages.rocm-smi
    vulkan-loader
    vulkan-tools
    vulkan-validation-layers
  ];

  environment.variables = {
    LIBVA_DRIVER_NAME = "radeonsi";
  };

}
