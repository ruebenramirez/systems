# This config is only to contain x11 and gui pkgs
{ config, pkgs, betterbird-stable, ... }:

let

in
{

  environment = {
    systemPackages = with pkgs; [

      libimobiledevice # internet via iPhone usb tethering

    ];
  };
      

  # internet via iPhone usb-tethering
  services.usbmuxd = {
    enable = true;
    package = pkgs.usbmuxd2;
  };

}
