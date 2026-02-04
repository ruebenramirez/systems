{ config, pkgs, ... }:

let
  vendorId = "05ac";
  productId = "024f";

  # Ensure we have the right paths for NixOS
  swaySocketCheck = ''
    SWAY_PID=$( ${pkgs.procps}/bin/pgrep -u 1000 -x sway )
    if [ -z "$SWAY_PID" ]; then
      echo "$(date): Sway not running, skipping toggle." >> /tmp/kbd-toggle.log
      exit 0
    fi
    export SWAYSOCK="/run/user/1000/sway-ipc.1000.$SWAY_PID.sock"
  '';

  disableKbd = pkgs.writeShellScript "disable-thinkpad-kbd" ''
    ${swaySocketCheck}
    ${pkgs.sway}/bin/swaymsg input "1:1:AT_Translated_Set_2_keyboard" events disabled
    echo "$(date): [ADD] Lofree connected - Thinkpad keyboard disabled" >> /tmp/kbd-toggle.log
  '';

  enableKbd = pkgs.writeShellScript "enable-thinkpad-kbd" ''
    ${swaySocketCheck}
    ${pkgs.sway}/bin/swaymsg input "1:1:AT_Translated_Set_2_keyboard" events enabled
    echo "$(date): [REMOVE] Lofree disconnected - Thinkpad keyboard enabled" >> /tmp/kbd-toggle.log
  '';
in
{
  services.udev.extraRules = ''
    # Match the 'add' event using physical attributes
    ACTION=="add", SUBSYSTEM=="usb", ATTRS{idVendor}=="${vendorId}", ATTRS{idProduct}=="${productId}", RUN+="${disableKbd}"

    # Match the 'remove' event using environment variables and product string
    # We target the 'usb_device' type to ensure we only trigger once per unplug
    ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{PRODUCT}=="5ac/24f/*", RUN+="${enableKbd}"
  '';
}
