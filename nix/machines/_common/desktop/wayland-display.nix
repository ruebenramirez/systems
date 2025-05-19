{ config, pkgs, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    gammastep
    kanshi
    light
    mako
    rofi-wayland
    swayidle
    wdisplays
    wl-clipboard
    wtype
    xdg-utils
  ];

  environment.variables = {
    NIXOS_OZONE_WL = "1";
  };

  # kanshi manages displays my sway setup
  systemd.user.services.kanshi = {
    description = "kanshi dynamic display congfiguration daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''${pkgs.kanshi}/bin/kanshi -c /etc/kanshi/config'';
    };
  };

  environment.etc."kanshi/config" = {
    text = ''
      profile thinkpad_undocked {
        output "California Institute of Technology 0x1404 Unknown" mode 1920x1200 position 0,0
      }

      profile thinkpad_standing_desk {
        output "California Institute of Technology 0x1404 Unknown" mode 1920x1200 position 0,0
        output "GWD ARZOPA " mode 2560x1600 position 1920,0 scale 1.20
      }

      profile thinkpad_three_monitor_desk {
        output "California Institute of Technology 0x1404 Unknown" mode 1920x1200 position 214,0 scale 1.00
        output "GWD ARZOPA 0x70320205" mode 2560x1600 position 0,1200 scale 1.20
        output "LG Electronics LG HDR 4K 406NTZNA2149" mode 3840x2160 position 2134,0 scale 1.00
      }

      # # horizontal display configuration
      # profile thinkpad_two_monitor_desk {
      #   output "California Institute of Technology 0x1404 Unknown" mode 1920x1200 position 0,0 scale 1.00
      #   output "LG Electronics LG HDR 4K 406NTZNA2149" mode 3840x2160 position 1920,0 scale 1.00
      # }

      # vertical display configuration
      profile thinkpad_two_monitor_desk {
        output "California Institute of Technology 0x1404 Unknown" mode 1920x1200 position 214,0 scale 1.00
        output "GWD ARZOPA 0x70320205" mode 2560x1600 position 0,1200 scale 1.20
      }

      profile xps17_undocked {
        output eDP-1 mode 3840x2400@60Hz position 0,0
      }

      profile xps17_desk {
        output "Sharp Corporation 0x1517 Unknown" mode 3840x2400 position 640,0 scale 2.00
        output "LG Electronics LG HDR 4K 406NTZNA2149" mode 3840x2160 position 2560,0 scale 1.00
        output "GWD ARZOPA 0x70320205" mode 2560x1600 position 0,1200 scale 1.20
      }
    '';
    mode="0644";
  };

}
