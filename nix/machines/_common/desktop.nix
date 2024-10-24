# This config is only to contain shared desktop configuration
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
    _1password
    _1password-gui # password manager
    alacritty # terminal emulator of choice
    arandr # ui xrandr tool for interacting the multimonitors
    autorandr # cli xrandr tool for saving/load profiles
    barrier # share mouse and keyboard across multiple machines
    gnome.cheese # webcam camera tool
    gnome.nautilus # file browser
    obsidian # notes
    remmina  # best RDP client
    speedtest-cli # test internet connection bandwidth
    viewnior # image viewer

    # core behind the scenes tools
    acpi # battery life monitoring
    libnotify # notifications on the desktop
    light # screen brightness management
    polkit # auth security?
    polkit_gnome # auth security?

    # mounting filesystems
    exfat
    ntfs3g
    udiskie # automount attached usb disks

    # books and whitepapers related
    calibre # manage ebooks
    koreader
    mupdf # pdf viewer with vim keybindings
    xournal # pdf annotations

    # comms
    gomuks # matrix
    betterbird-stable.betterbird # email client (fork of thunderbird)
    discord # projects/gaming chat app
    element-desktop #matrix chat desktop client
    signal-desktop # signal chat app
    slack # work chat app
    zoom-us # meeting software

    # web browsers
    brave # browser that protects privacy and blocks a lot of ads
    firefox
    ungoogled-chromium
    google-chrome
    tor-browser-bundle-bin

    # media players
    cmus
    gpodder # podcast listener desktop app (syncs progress with antennapod android podcast app)
    mpv # media player
    playerctl # media controls for applications running on linux
    vlc # video player with lots format compatibility

    # media editing
    drawio # sketch draw and diagram
    obs-studio # screen recording
    gimp-with-plugins
    inkscape-with-extensions

    # VPN
    tailscale
    openvpn

    # screenshot ands ocr screenshot deps
    tesseract
    imagemagick
    grim
    slurp

    # dev related
    vscode.fhs # VSCode editor with unmanaged plugin controls

    # bluetooth audio
    pulseaudio  # for pactcl
    pulsemixer  # like pwvucontrol for the CLI
    bluez-tools
    libopenaptx # aptX high quality audio codec
    pwvucontrol # audio control GUI
    bluetuith # CLI bluetooth device management

    # wayland specific
    gammastep
    kanshi
    mako
    rofi-wayland
    swayidle
    wdisplays
    wl-clipboard
    xdg-utils
  ];


  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  fonts.packages = with pkgs; [
    source-code-pro
  ];

  # light is a backlight management utility
  programs.light.enable = true;

  # bluetooth audio related
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

  # kanshi manages displays my sway setup
  systemd.user.services.kanshi = {
    description = "kanshi dynamic display congfiguration daemon";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''${pkgs.kanshi}/bin/kanshi'';
    };
  };

  # logitech dongle support
  hardware.logitech.wireless.enable = true;

  # 1password system auth
  security.polkit.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "rramirez" ];
  };

  services.udisks2 = {
    enable = true;
  };
}
