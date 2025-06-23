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
    # Ensure we have the ARM64 binary cache
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
    ];

    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # Optimize build performance
    max-jobs = "auto";
    cores = 0; # Use all available cores

    # Increase timeout for ARM builds (they can be slow)
    stalled-download-timeout = 300;
    timeout = 0; # Disable timeout for long builds
  };

  # Optional: Create a convenience script for Pi image building
  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "build-pi-image" ''
      #!/usr/bin/env bash
      set -euo pipefail

      FLAKE_PATH=''${1:-"."}
      ATTR=''${2:-"raspberry-pi"}

      echo "Building Raspberry Pi image..."
      echo "Flake: $FLAKE_PATH"
      echo "Attribute: $ATTR"
      echo ""
      echo "This may take 15-30 minutes due to ARM64 emulation..."
      echo ""

      nix build "$FLAKE_PATH#nixosConfigurations.$ATTR.config.system.build.sdImage" \
        --show-trace \
        --verbose

      if [ $? -eq 0 ]; then
        echo ""
        echo "✅ Build successful!"
        echo "Image location: $(readlink result)/sd-image/*.img"
        echo ""
        echo "Flash to SD card with:"
        echo "  sudo dd if=\$(readlink result)/sd-image/*.img of=/dev/sdX bs=4M status=progress conv=fsync"
        echo "  (Replace /dev/sdX with your SD card device)"
        echo ""
        echo "Find SD card device with: lsblk"
      else
        echo "❌ Build failed!"
        exit 1
      fi
    '')
  ];
}
