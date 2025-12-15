# This config is only to contain shared desktop configuration
{ config, pkgs, ... }:

let

in
{
  imports = [
    ./onepassword.nix
    ./bluetooth-audio.nix
    ./wayland-display.nix
    ./lofree-keyboard-function-key-access.nix
  ];

  # install Desktop packages
  environment.systemPackages = with pkgs; [
    aerc
    arandr # ui xrandr tool for interacting the multimonitors
    autorandr # cli xrandr tool for saving/load profiles
    cheese # webcam camera tool
    finamp #jellyfin music client
    libreoffice
    remmina  # best RDP client
    thunderbird
    timer # fancy js cli timer
    viewnior # image viewer
    ydotool

    # Terminal Emulators
    alacritty
    ghostty
    wezterm

    # file browser and google drive integration
    insync
    insync-nautilus

    # auth-related desktop backend services
    acpi
    libnotify
    pmutils
    polkit
    polkit_gnome
    exfat
    ntfs3g
    udiskie # automount attached usb disks

    # books and whitepapers related
    calibre # manage ebooks
    koreader
    mupdf # pdf viewer with vim keybindings

    # comms
    discord # projects/gaming chat app
    element-desktop #matrix chat desktop client
    signal-desktop # signal chat app
    slack # work chat app
    zoom-us # meeting software

    # web browsers
    brave
    firefox
    tor-browser
    ungoogled-chromium

    # media players
    cmus
    gpodder # podcast listener desktop app (syncs progress with antennapod android podcast app)
    mpv # media player
    playerctl # media controls for applications running on linux
    vlc # video player with lots format compatibility
    ffmpeg

    # media editing
    # drawio # sketch draw and diagram
    # obs-studio # screen recording
    # gimp-with-plugins
    # inkscape-with-extensions

    # screenshot ands ocr screenshot deps
    tesseract
    imagemagick
    grim
    slurp
    ocrmypdf
    satty
  ];


  fonts.packages = with pkgs; [
    nerd-fonts.sauce-code-pro
  ];

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # light is a backlight management utility
  programs.light.enable = true;


  # sway window management on wayland (replacing i3)
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  xdg.mime.enable = true;
  xdg.mime.defaultApplications = {
    "text/plain" = "nvim.desktop";
  };

  services.udisks2 = {
    enable = true;
  };

  # ydotool for keyboard-based click automation
  programs.ydotool = {
    enable = true;
  };

  # Tell ydotool where the socket for the daemon is
  environment.variables = {
    YDOTOOL_SOCKET = "/run/ydotoold/socket";
  };

}
