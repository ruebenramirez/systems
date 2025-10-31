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
    arandr # ui xrandr tool for interacting the multimonitors
    autorandr # cli xrandr tool for saving/load profiles
    cheese # webcam camera tool
    aerc
    finamp #jellyfin client
    libreoffice
    obsidian # notes
    remmina  # best RDP client
    timer
    viewnior # image viewer
    ydotool

    # Terminal Emulators
    alacritty
    ghostty
    wezterm

    # file browser and google drive integration
    nautilus # file browser
    insync
    insync-nautilus
    insync-emblem-icons

    # core behind the scenes tools
    acpi
    libnotify
    pmutils
    polkit
    polkit_gnome

    # mounting filesystems
    exfat
    ntfs3g
    udiskie # automount attached usb disks

    # books and whitepapers related
    calibre # manage ebooks
    foliate # ebook reader
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
    tor-browser-bundle-bin

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

    # Network and VPN
    tailscale
    wireguard-tools

    # screenshot ands ocr screenshot deps
    tesseract
    imagemagick
    grim
    slurp
    ocrmypdf
    satty

    # dev related
    vscode.fhs # VSCode editor with unmanaged plugin controls
    nerdctl

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

  services.udisks2 = {
    enable = true;
  };

  # Set LibreWolf as default browser
  xdg.mime.defaultApplications = {
    "text/html" = "librewolf.desktop";
    "x-scheme-handler/http" = "librewolf.desktop";
    "x-scheme-handler/https" = "librewolf.desktop";
    "x-scheme-handler/about" = "librewolf.desktop";
    "x-scheme-handler/unknown" = "librewolf.desktop";
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
