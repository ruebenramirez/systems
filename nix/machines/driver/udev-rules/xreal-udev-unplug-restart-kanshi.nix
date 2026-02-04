{ config, pkgs, ... }:

let
  # Simple script to trigger a full Sway reload
  swayReload = pkgs.writeShellScript "sway-reload-script" ''
    # 1. Wait 2 seconds for the hardware state to settle
    sleep 2

    # 2. Find the Sway socket for your user
    SWAY_PID=$( ${pkgs.procps}/bin/pgrep -u 1000 -x sway )
    if [ -n "$SWAY_PID" ]; then
      export SWAYSOCK="/run/user/1000/sway-ipc.1000.$SWAY_PID.sock"

      # 3. Issue a full reload command
      ${pkgs.sway}/bin/swaymsg reload

      echo "$(date): Sway reload triggered via XREAL removal" >> /tmp/kanshi.log
    fi
  '';
in
{
  services.udev.extraRules = ''
    # Trigger a full Sway reload when the XREAL glasses are unplugged
    ACTION=="remove", SUBSYSTEM=="usb", ENV{PRODUCT}=="3318/43e/*", RUN+="${swayReload}"
  '';
}
