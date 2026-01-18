#!/usr/bin/env bash

user_id=1000

# Set environment for Sway
export SWAYSOCK="/run/user/$user_id/sway-ipc.$user_id.$(pgrep -x sway).sock"

# Log the action
echo "$(date): Enabling laptop keyboard - Flow84@Lofree disconnected" >> /tmp/keyboard-toggle.log

# Re-enable the laptop keyboard via Sway using exact identifier
swaymsg input "1:1:AT_Translated_Set_2_keyboard" events enabled

exit 0
