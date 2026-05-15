#!/usr/bin/env bash

# Check if the OpenRazer daemon is accessible
if ! systemctl --user is-active --quiet openrazer-daemon.service; then
    echo "Starting openrazer-daemon..."
    systemctl --user start openrazer-daemon.service
fi

# Set the lighting effect to static white (#FFFFFF)
polychromatic-cli --option static -c "#FFFFFF"

echo "Backlighting set to white."
