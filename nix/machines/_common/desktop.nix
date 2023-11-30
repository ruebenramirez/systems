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
    _1password
    _1password-gui # password manager
    alacritty # terminal emulator of choice
    arandr # ui xrandr tool for interacting the multimonitors
    authy # OTP app
    autorandr # cli xrandr tool for saving/load profiles
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
    light # screen brightness management
    mpv
    mupdf # pdf viewer with vim keybindings
    myFirefox # robs custom firefox
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
    xournal # pdf annotations
    xsel # deps for ocr screenshot
    zathura # simple pdf viewer
    zoom-us
    libnotify
    betterbird


    geoclue2
    redshift

    # TODO: configure Razer Huntsman V2 TKL
    # razergenie
    # openrazer-daemon

    acpi # battery life monitoring

    tor-browser-bundle-bin

    # 1password system authentication security requirement
    polkit
    polkit_gnome
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
        dunst
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

  programs.light.enable = true;
}
