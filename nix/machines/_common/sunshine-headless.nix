{ config, pkgs, lib, ... }:

let
  username = "rramirez";
  swayConfig = pkgs.writeText "sway-sunshine-config" ''
    # Minimal headless sway config for sunshine streaming
    # No status bar, wallpaper, idle, or lock screen

    # Suppress swaynag popups for config errors
    set $swaynag_command ${pkgs.sway}/bin/swaynag

    # Low latency for streaming
    output * {
      allow_tearing yes
      max_render_time off
      bg #111111 solid_color
    }

    # Enable Xwayland for Steam's 32-bit X11 client
    xwayland enable
  '';
in
{
  # Load the uinput kernel module to allow virtual input device creation
  hardware.uinput.enable = true;

  security.pam.loginLimits = [
    { domain = username; item = "nice"; type = "-"; value = "-20"; }
  ];

  security.wrappers.sunshine = lib.mkForce {
    owner = "root";
    group = "root";
    capabilities = "cap_sys_admin,cap_sys_nice+ep";
    source = "${pkgs.sunshine}/bin/sunshine";
  };

  # Enable sunshine service (user service that starts on graphical-session.target)
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
  };
  networking.firewall.allowedTCPPorts = [
    48010
    47984
    47989
  ];
  networking.firewall.allowedUDPPorts = [
    47998
    47999
    48000
    48002
    48010
  ];

  # Enable lingering so user services run at boot without login
  # Add input group for sway headless + libinput access
  users.users.${username} = {
    linger = true;
    extraGroups = lib.mkBefore [
      "input"
      "uinput"
    ];
  };

  # Minimal sway config for headless streaming
  environment.etc."sway/sunshine/config" = {
    source = swayConfig;
    mode = "0644";
  };

  # Headless sway service that starts at boot via lingering
  systemd.user.services.sway-headless = {
    description = "Headless sway compositor for sunshine game streaming";
    documentation = [ "man:sway(5)" ];
    wantedBy = [ "default.target" ];
    partOf = [ "default.target" ];

    serviceConfig = {
      Type = "simple";
      Environment = [
        "WLR_BACKENDS=headless,libinput"
        "WLR_RENDERER=gles2"
        "WLR_RENDERER_ALLOW_SOFTWARE=1"
        "LIBSEAT_BACKEND=noop"
        "WLR_LIBINPUT_NO_DEVICES=1"
      ];
      ExecStart = "${pkgs.sway}/bin/sway -c /etc/sway/sunshine/config";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Override sunshine to start directly on default.target after sway is ready
  systemd.user.services.sunshine = {
    after = [ "sway-headless.service" ];
    wants = [ "sway-headless.service" ];
    wantedBy = lib.mkForce [ "default.target" ];

    serviceConfig = {
      Environment = [
        "WAYLAND_DISPLAY=wayland-1"
        "XDG_RUNTIME_DIR=/run/user/1000"
        "DISPLAY=:0"
      ];
    };
  };
}
