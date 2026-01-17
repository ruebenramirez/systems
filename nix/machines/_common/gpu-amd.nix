{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    (btop.override { rocmSupport = true; })
    amdgpu_top
    clinfo
    libva-utils
    nvtopPackages.amd
    rocmPackages.rocminfo
    vulkan-loader
    vulkan-tools
    vulkan-validation-layers
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      libva
      libvdpau-va-gl
      rocmPackages.clr.icd
      libvdpau-va-gl
    ];
  };
}
