#!/usr/bin/env bash

# Function for Alacritty windows
launch_terminal() {
    local ws=$1
    local class=$2
    local cmd=$3
    # Check if this class is already running to prevent duplicates on reload
    if ! pgrep -f "alacritty --class $class" > /dev/null; then
        swaymsg "workspace $ws; exec alacritty --class $class -e bash -c '$cmd'"
        sleep 1
    fi
}

# 1: btop (Uncomment if you want it active)
# launch_terminal 1 "stats" "btop"

# 3: Notes session
launch_terminal 3 "notes" "cd ~/notes"

# 4: Workstation SSH
launch_terminal 4 "workstation" "ssh xps17-proxy"

# 7: 1Password
pgrep -x 1password > /dev/null || swaymsg "workspace 7; exec 1password"

# 8: Thunderbird
pgrep -x thunderbird > /dev/null || swaymsg "workspace 8; exec thunderbird"

# 9: Brave (Homepage)
# Launching the main browser instance
if ! pgrep -x brave > /dev/null; then
    swaymsg "workspace 9; exec brave"
    sleep 1
fi

# 10: Cheogram and Signal
swaymsg "workspace 10"
# Use --app for Cheogram to give it a unique window class
if ! pgrep -f "app.cheogram.com" > /dev/null; then
    exec brave --app=https://app.cheogram.com &
fi

if ! pgrep -x signal-desktop > /dev/null; then
    exec signal-desktop &
fi

sleep 2

# Return to Workspace 9
swaymsg "workspace 9"
