# Build Machine Configuration
# Enables cross-compilation for ARM64 targets like Raspberry Pi

{ config, pkgs, ... }:

{
  # Enable ARM64 emulation for cross-compilation
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # Build-related packages
  environment.systemPackages = with pkgs; [
    # Image compression/decompression tools
    zstd                    # For handling compressed NixOS images

    # Development and debugging tools for embedded/ARM
    minicom                 # Serial terminal
    picocom                 # Alternative serial terminal

    # Useful for SD card management
    parted                  # Disk partitioning
    dosfstools              # FAT filesystem tools
  ];

  # Optimize Nix settings for cross-compilation builds
  nix.settings = {
    # Optimize build performance
    max-jobs = "auto";
    cores = 0; # Use all available cores

    # Increase timeout for ARM builds (they can be slow)
    stalled-download-timeout = 300;
    timeout = 0; # Disable timeout for long builds
  };

}
