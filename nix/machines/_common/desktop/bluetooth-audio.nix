# This config is only to contain shared desktop configuration
{ config, pkgs, ... }:

let

in
{

  # bluetooth audio

  environment.systemPackages = with pkgs; [
    pulseaudio  # for pactcl
    pulsemixer  # like pwvucontrol for the CLI
    bluez-experimental
    bluez-tools
    libopenaptx # aptX high quality audio codec
    pwvucontrol # audio control GUI
    bluetuith # CLI bluetooth device management
  ];


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
  hardware.bluetooth = {
    enable = true;
    settings = {
      General = {
        # enable mpris-proxy (bluetooth headphone media controls)
        Experimental = true;
      };
    };
  };

  # load MRPIS into dbus (bluetooth headphone media controls)
  services.dbus.packages = [ pkgs.bluez];


}
