{ config, pkgs, ... }:

let
  mountNikon = pkgs.writeShellScript "mount-nikon" ''
    # Wait for the camera to finish its internal 'Upload Priority' check
    sleep 2

    # Format the bus and device numbers to 3 digits (e.g., 6 -> 006)
    BUS=$(printf "%03d" "$1")
    DEV=$(printf "%03d" "$2")

    # Export the DBus address so gio can find your Nautilus session
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u rramirez)/bus"

    # use systemd-run to execute the command inside the user's session.
    # This ensures it has the correct DBUS_SESSION_BUS_ADDRESS and environment.
    ${pkgs.systemd}/bin/systemd-run --user --machine=rramirez@.host \
      --description="Auto-mount Nikon Z8" \
      ${pkgs.glib}/bin/gio mount gphoto2://[usb:$BUS,$DEV]/
  '';
in

{
  # GVFS for MTP/Nautilus auto-mounting
  services.gvfs.enable = true;
  services.udisks2.enable = true;

  environment.sessionVariables = {
    GIO_EXTRA_MODULES = [ "${pkgs.gvfs}/lib/gio/modules" ];
    XDG_DATA_DIRS = [ "${pkgs.gvfs}/share" ];
  };

  # Make sure the DBus service files from gvfs are globally visible
  services.dbus.packages = [ pkgs.gvfs ];

  # This replaces android-udev-rules and sets up the necessary hardware permissions
  programs.adb.enable = true;

  # Packages for MTP access (Nautilus + CLI tools)
  environment.systemPackages = with pkgs; [
    nautilus              # GNOME Files
    glib
    libmtp
    libgphoto2
    jmtpfs
    android-file-transfer # Fallback GUI
    gphoto2
  ];

  # Add your user to the adbusers group (replaces/complements plugdev)
  users.users.rramirez.extraGroups = [ "adbusers" "plugdev" ];

  # Udev rule specifically for Nikon Z8 PTP mode
  services.udev.extraRules = ''
    SUBSYSTEM=="usb", ACTION=="add", ATTR{idVendor}=="04b0", ATTR{idProduct}=="0451", \
    RUN+="${mountNikon} $attr{busnum} $attr{devnum}"
  '';
}
