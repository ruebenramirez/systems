# This config is only to contain x11 and gui pkgs
{ config, pkgs, ... }:

let
  # Nix firefox addons only work with the firefox-esr package.
  # https://github.com/NixOS/nixpkgs/blob/master/doc/builders/packages/firefox.section.md
  # myFirefox = pkgs.wrapFirefox pkgs.firefox-esr-unwrapped {
  #   cfg = { smartcardSupport = true; };
  #   nixExtensions = [
  #     (pkgs.fetchFirefoxAddon {
  #       name = "ublock"; # Has to be unique!
  #       url = "https://addons.mozilla.org/firefox/downloads/file/4047353/ublock_origin-1.46.0.xpi"; # Get this from about:addons
  #       sha256 = "sha256-a/ivUmY1P6teq9x0dt4CbgHt+3kBsEMMXlOfZ5Hx7cg=";
  #     })
  #     (pkgs.fetchFirefoxAddon {
  #       name = "zoomScheduler";
  #       url = "https://addons.mozilla.org/firefox/downloads/file/4048126/zoom_new_scheduler-2.1.37.xpi";
  #       sha256 = "sha256-Tj8DU5fxLIp3UgHZfD4hMhO/yKiQNlzCa1U6dOVjVAY=";
  #     })
  #     # TODO: add vimium
  #     # TODO: add 1password
  #   ];
  # };
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
    betterbird # email client (fork of thunderbird)
    blueman # bluetooth device management
    brave
    calibre # manage ebooks
    chromium
    betterbird
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
    light # screen brightness management
    mpv
    mupdf # pdf viewer with vim keybindings
    firefox
    #myFirefox # robs custom firefox
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
    tesseract5 # deps for ocr screenshot
    udiskie # automount attached usb disks
    ungoogled-chromium
    usbutils # contains lsusb tool
    viewnior
    vlc # video player with lots format compatibility
    vscode
    xbindkeys # keyboard shortcuts
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

    xkb = {
      layout = "us";
      # swap caps and escape keys + swap alt and win keys
      options = "caps:escape, altwin:swap_alt_win";
    };

  };
  services.libinput.enable = true;

  services.displayManager = {
    defaultSession = "none+i3";
  };

  fonts.packages = with pkgs; [
    source-code-pro
  ];

  programs.light.enable = true;
}
