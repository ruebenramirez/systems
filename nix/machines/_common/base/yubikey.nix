{ config, pkgs, pkgs-unstable, ... }:
{
  # Enable the SmartCard Daemon (required for most Yubikey functions)
  services.pcscd.enable = true;

  # Essential packages for managing Yubikeys
  environment.systemPackages = with pkgs; [
    yubikey-manager       # CLI tool (ykman)
    yubikey-personalization # For HMAC-SHA1 challenge-response
    yubioath-flutter      # Desktop Authenticator app
    yubikey-touch-detector # Notifies you when the key needs a touch
  ];

  # Enable udev rules for Yubikey devices
  services.udev.packages = with pkgs; [
    yubikey-personalization
    libu2f-host
  ];

  # Optional: Enable GPG agent with SSH support if using Yubikey for PIV/GPG
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };
}
