
{ config, pkgs, ... }:

let

in
{


  # Enable graphics hardware acceleration
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      # VA-API support for AMD GPUs
      vaapiVdpau
      libvdpau-va-gl
      # OpenCL support for AMD GPUs (required for tone mapping and subtitle burn-in)
      rocmPackages.clr.icd
    ];
  };

  # Set VA-API driver for AMD
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "radeonsi";
  };

  # Configure Jellyfin service with hardware acceleration environment
  systemd.services.jellyfin = {
    environment = {
      LIBVA_DRIVER_NAME = "radeonsi";
    };
    # Ensure jellyfin user has access to render group for GPU access
    serviceConfig = {
      SupplementaryGroups = [ "render" "video" ];
    };
  };

  services.jellyfin = {
    enable = true;
    openFirewall = true;
    user="rramirez";
  };

  environment.systemPackages = with pkgs; [
    jellyfin
    jellyfin-web
    jellyfin-ffmpeg
    libva-utils  # provides vainfo command
    clinfo       # provides clinfo command for OpenCL verification
  ];

  # Add user to required groups for GPU access
  users.users.rramirez = {
    extraGroups = [ "video" "render" ];
  };
}
