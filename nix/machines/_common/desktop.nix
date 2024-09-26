# This config is only to contain x11 and gui pkgs
{ config, pkgs, betterbird-stable, ... }:

let

in
{
  # temporary for obsidian support
  nixpkgs.config.permittedInsecurePackages = [
    "olm-3.2.16"        # element dependency #TODO: read up on the OLM security issues upstream
  ];


  # install Desktop packages
  environment.systemPackages = with pkgs; [
    rclone
    _1password
    _1password-gui # password manager
    alacritty # terminal emulator of choice
    arandr # ui xrandr tool for interacting the multimonitors
    autorandr # cli xrandr tool for saving/load profiles
    barrier # share mouse and keyboard across multiple machines
    betterbird-stable.betterbird # email client (fork of thunderbird)
    blueman # bluetooth device management
    brave
    calibre # manage ebooks
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
    nm-tray # NetworkManager tray applet
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
    qrtool
    xdotool

    # screenshot ands ocr screenshot deps
    tesseract
    scrot
    xsel
    imagemagick
    grim
    slurp

    # genAI
    ollama

    # unmanaged vscode
    vscode.fhs

    # VPN
    tailscale
    openvpn

    # media editing
    gimp-with-plugins
    inkscape-with-extensions

    # davinci-resolve # disabling because problem with python2.7 being insecure

    wine
    wine64
    winetricks
    winePackages.fonts
    drawio
    koreader

    bluez-tools
    pulseaudio  # for pactcl
    #libldac     # not working currently # LDAC codec
    libopenaptx    # aptX codec
    fdk_aac     # AAC codec
    pwvucontrol
  ];


  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;
  services.displayManager = {
    defaultSession = "none+i3";
  };

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


    xkb = {
      layout = "us";

      # swap caps and escape keys + swap alt and win keys
      options = "caps:escape, altwin:swap_alt_win";
    };
  };

  fonts.packages = with pkgs; [
    source-code-pro
  ];

  # light is a backlight management utility
  programs.light.enable = true;


  # sourced from: https://github.com/TLATER/dotfiles/blob/a31d74856710936b398318062f0af6616d994eba/nixos-config/default.nix#L154
  services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;

      # Disable the HFP bluetooth profile, because I always use external
      # microphones anyway. It sucks and sometimes devices end up caught
      # in it even if I have another microphone.
      wireplumber.extraConfig = {
        "50-bluez" = {
          "monitor.bluez.rules" = [
            {
              matches = [ { "device.name" = "~bluez_card.*"; } ];
              actions = {
                update-props = {
                  "bluez5.auto-connect" = [
                    "a2dp_sink"
                    "a2dp_source"
                  ];
                  "bluez5.hw-volume" = [
                    "a2dp_sink"
                    "a2dp_source"
                  ];
                };
              };
            }
          ];
          "monitor.bluez.properties" = {
            "bluez5.roles" = [
              "a2dp_sink"
              "a2dp_source"
              "bap_sink"
              "bap_source"
            ];

            "bluez5.codecs" = [
              "ldac"
              "aptx"
              "aptx_ll_duplex"
              "aptx_ll"
              "aptx_hd"
              "opus_05_pro"
              "opus_05_71"
              "opus_05_51"
              "opus_05"
              "opus_05_duplex"
              "aac"
              "sbc_xq"
            ];

            "bluez5.hfphsp-backend" = "none";
          };
        };
      };
    };

    services.blueman.enable = true;
    hardware.bluetooth.enable = true;
}
