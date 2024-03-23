# This config is only to contain x11 and gui pkgs
{ config, pkgs, betterbird-stable, ... }:

let

in
{
  # temporary for obsidian support
  nixpkgs.config.permittedInsecurePackages = [ "electron-25.9.0" ];


  # install Desktop packages
  environment.systemPackages = with pkgs; [
    rclone
    _1password
    _1password-gui # password manager
    alacritty # terminal emulator of choice
    arandr # ui xrandr tool for interacting the multimonitors
    autorandr # cli xrandr tool for saving/load profiles
    betterbird-stable.betterbird # email client (fork of thunderbird)
    blueman # bluetooth device management
    brave
    calibre # manage ebooks
    chromium
    discord # projects/gaming chat app
    dmidecode # reads info from connected hardware
    element-desktop #matrix chat desktop client
    feh # set wallpaper
    flameshot # screenshot tool
    gnome.cheese # webcam camera tool
    gnome.nautilus # file browser
    gomuks # matrix
    google-chrome
    imagemagick # dup might be a problem?
    kitty # terminal
    light # screen brightness management
    mpv
    mupdf # pdf viewer with vim keybindings
    firefox
    obs-studio # screen recording
    obsidian # notes
    pasystray # task bar applet for sound management
    pavucontrol # sound management
    pciutils # contains the lspci tool
    powertop # power management profiling tool
    remmina
    scrot # deps for ocr screenshot
    signal-desktop # signal chat app
    slack # work chat app
    speedtest-cli
    tesseract5 # deps for ocr screenshot
    udiskie # automount attached usb disks
    ungoogled-chromium
    usbutils # contains lsusb tool
    viewnior
    vlc # video player with lots format compatibility
    vscode.fhs
    xbindkeys # keyboard shortcuts
    xcalib
    xclip
    xournal # pdf annotations
    xsel # deps for ocr screenshot
    zathura # simple pdf viewer
    zoom-us
    libnotify
    acpi # battery life monitoring
    tor-browser-bundle-bin
    polkit
    polkit_gnome
    xdotool

    # ocr screenshot text
    tesseract
    scrot
    xsel
    imagemagick
  ];

  services.xserver = {
    enable = true;
    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      defaultSession = "none+i3";
    };

    # This is the way
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu # simple launcher
        i3status # default i3 status bar
        i3lock # default + simple lock that matches my config
        dunst
      ];
    };

    # Enable touchpad support (enabled default in most desktopManager).
    libinput.enable = true;

    layout = "us";
    # swap caps and escape keys + swap alt and win keys
    xkbOptions = "caps:escape, altwin:swap_alt_win";
  };

  fonts.packages = with pkgs; [
    source-code-pro
  ];

  programs.light.enable = true;
}
