#!/usr/bin/env bash

TIMEOUT=15
user_id=1000
FORCE=false

# Parse flags
while getopts "f" opt; do
  case $opt in
    f) FORCE=true ;;
    *) echo "Usage: $0 [-f]"; exit 1 ;;
  esac
done

disable_thinkpad_keyboard() {
    export SWAYSOCK="/run/user/$user_id/sway-ipc.$user_id.$(pgrep -u $user_id -x sway).sock"
    swaymsg input "1:1:AT_Translated_Set_2_keyboard" events disabled
    echo "thinkpad keyboard disabled"
}

enable_thinkpad_keyboard() {
    export SWAYSOCK="/run/user/$user_id/sway-ipc.$user_id.$(pgrep -u $user_id -x sway).sock"
    swaymsg input "1:1:AT_Translated_Set_2_keyboard" events enabled
    echo "thinkpad keyboard enabled"
}

timeout_wait() {
    echo ""
    echo "Waiting $TIMEOUT seconds before re-enabling thinkpad keyboard"
    echo "<Ctrl>-c to cancel"
    sleep $TIMEOUT
}

main() {
    disable_thinkpad_keyboard

    if [ "$FORCE" = false ]; then
        timeout_wait
        enable_thinkpad_keyboard
    fi
    exit 0
}

main
