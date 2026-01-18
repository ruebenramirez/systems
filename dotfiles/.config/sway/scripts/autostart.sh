#!/usr/bin/env bash

# Function for Alacritty windows
launch_terminal() {
    local ws=$1
    local class=$2
    local cmd=$3
    swaymsg "workspace $ws; exec alacritty --class $class -e bash -c '$cmd'"
    sleep 1
}

# 1: btop
#launch_terminal 1 "stats" "btop"

# 3: Notes session
launch_terminal 3 "notes" "ssh xps17-proxy -t 'cd ~/notes/ && tmux new-session -A -s notes nvim'"

# 4: Workstation SSH
launch_terminal 4 "workstation" "ssh xps17-proxy"

# 7: 1Password
swaymsg "workspace 7; exec 1password"

# 8: Thunderbird
swaymsg "workspace 8; exec thunderbird"

# 9: Firefox (Homepage)
swaymsg "workspace 9; exec firefox"

# 10: Cheogram and Signal
# We launch Cheogram in a new Firefox window
swaymsg "workspace 10"
exec firefox --new-window https://app.cheogram.com &
exec signal-desktop &
sleep 2

# Return to Workspace 9
swaymsg "workspace 9"


