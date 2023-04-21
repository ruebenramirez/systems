# This config is only to contain x11 and gui pkgs
{ config, pkgs, ... }:

let
  # Nix firefox addons only work with the firefox-esr package.
  # https://github.com/NixOS/nixpkgs/blob/master/doc/builders/packages/firefox.section.md
  myFirefox = pkgs.wrapFirefox pkgs.firefox-esr-unwrapped {
    cfg = { smartcardSupport = true; };
    nixExtensions = [
      (pkgs.fetchFirefoxAddon {
        name = "ublock"; # Has to be unique!
        url = "https://addons.mozilla.org/firefox/downloads/file/4047353/ublock_origin-1.46.0.xpi"; # Get this from about:addons
        sha256 = "sha256-a/ivUmY1P6teq9x0dt4CbgHt+3kBsEMMXlOfZ5Hx7cg=";
      })
      (pkgs.fetchFirefoxAddon {
        name = "zoomScheduler";
        url = "https://addons.mozilla.org/firefox/downloads/file/4048126/zoom_new_scheduler-2.1.37.xpi";
        sha256 = "sha256-Tj8DU5fxLIp3UgHZfD4hMhO/yKiQNlzCa1U6dOVjVAY=";
      })
      # TODO: add vimium
      # TODO: add 1password
    ];
  };
in
{
  # install Desktop packages
  environment.systemPackages = with pkgs; [
    myFirefox # robs custom firefox
    autorandr # cli xrandr tool for saving/load profiles
    arandr # ui xrandr tool for interacting the multimonitors
    chromium
    feh # set wallpaper
    gomuks # matrix
    zoom-us
    zathura # simple pdf viewer
    obsidian # notes
    viewnior
    mpv
    xournal # pdf annotations
    imagemagick # dup might be a problem?
    alacritty # terminal emulator of choice
    _1password-gui # password manager
    slack # work chat app
    discord # projects/gaming chat app
    flameshot # screenshot tool
    powertop # power management profiling tool
    pavucontrol # sound management
    pasystray # task bar applet for sound management
    teams # microsoft teams chat app
    light # screen brightness management
    pciutils # contains the lspci tool
    signal-desktop # signal chat app
    gnome.nautilus # file browser
    authy # OTP app
    blueman # bluetooth device management
    xbindkeys # keyboard shortcuts
    tesseract5 # deps for ocr screenshot
    scrot # deps for ocr screenshot
    xsel # deps for ocr screenshot
    calibre # manage ebooks
    usbutils # contains lsusb tool
    mupdf # pdf viewer with vim keybindings
    vlc # video player with lots format compatibility
    gnome.cheese # webcam camera tool
    tor-browser-bundle-bin
    dmidecode # reads info from connected hardware
    razergenie
    openrazer-daemon
  ];

  services.xserver = {
    enable = true;

    desktopManager = {
      xterm.enable = false;
    };

    displayManager = {
      defaultSession = "none+i3";

      # make mouse cursor size larger
      #  - https://github.com/NixOS/nixpkgs/issues/22652#issuecomment-288846599
      #  - ties to https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/x11/display-managers/lightdm-greeters/gtk.nix
      #lightdm.greeters.gtk.iconTheme

    };
    # This is the way
    windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu # simple launcher
        i3status # default i3 status bar
        i3lock # default + simple lock that matches my config
      ];
    };

    # Enable touchpad support (enabled default in most desktopManager).
    libinput.enable = true;

    layout = "us";
    # swap caps and escape keys + swap alt and win keys
    xkbOptions = "caps:escape, altwin:swap_alt_win";
  };

  fonts.fonts = with pkgs; [
    source-code-pro
  ];
}
