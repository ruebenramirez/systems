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

# 1: btop
launch_terminal 1 "stats" "btop"

# 3: Notes session
launch_terminal 3 "notes" "cd ~/notes"

# 4: Workstation SSH
launch_terminal 4 "workstation" "hostname -f"

# 7: 1Password
pgrep -x 1password > /dev/null || swaymsg "workspace 7; exec 1password"

# 8: Thunderbird
pgrep -x thunderbird > /dev/null || swaymsg "workspace 8; exec thunderbird"

# 9: Firefox (Homepage)
swaymsg "workspace 9; exec firefox"

# 10: Cheogram and Signal
swaymsg "workspace 10"
exec firefox --new-window https://app.cheogram.com &
exec signal-desktop &
sleep 2

# Return to Workspace 9
swaymsg "workspace 9"
