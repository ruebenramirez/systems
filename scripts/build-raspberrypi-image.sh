#!/usr/bin/env bash
set -euo pipefail

nix flake update
FLAKE_PATH=''${1:-"."}
ATTR=''${2:-"raspberry-pi"}

echo "Building Raspberry Pi image..."
echo "Flake: $FLAKE_PATH"
echo "Attribute: $ATTR"
echo ""
echo "This may take 15-30 minutes due to ARM64 emulation..."
echo ""

nix build "./#nixosConfigurations.$ATTR.config.system.build.sdImage" \
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
