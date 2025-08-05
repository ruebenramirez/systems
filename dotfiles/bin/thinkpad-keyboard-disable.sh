#!/usr/bin/env bash

TIMEOUT=15

disable_thinkpad_keyboard() {
    export SWAYSOCK="/run/user/$(id -u)/sway-ipc.$(id -u).$(pgrep -x sway).sock"
    swaymsg input "1:1:AT_Translated_Set_2_keyboard" events disabled
    echo "thinkpad keyboard disabled"
}

timeout() {
    echo ""
    echo "Waiting $TIMEOUT seconds before re-enabling thinkpad keyboard"
    echo "<Ctrl>-c to cancel"
    sleep $TIMEOUT
}

enable_thinkpad_keyboard() {
    export SWAYSOCK="/run/user/$(id -u)/sway-ipc.$(id -u).$(pgrep -x sway).sock"
    swaymsg input "1:1:AT_Translated_Set_2_keyboard" events enabled
    echo "thinkpad keyboard disabled"
}

main() {
    disable_thinkpad_keyboard
    timeout
    enable_thinkpad_keyboard
    exit 0
}

main

