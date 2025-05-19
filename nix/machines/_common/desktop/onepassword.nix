{ config, pkgs, ... }:

let

in
{
  # 1password password manager and deps

  # Enable GNOME Keyring system-wide
  services.gnome.gnome-keyring.enable = true;

  # Enable PAM integration for automatic unlock
  security.pam.services.login.enableGnomeKeyring = true;

  # Install libsecret for command-line tools
  environment.systemPackages = with pkgs; [
    libsecret  # Provides secret-tool command
    _1password-cli
    _1password-gui
  ];

  # 1password system auth
  security.polkit.enable = true;
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "rramirez" ];
  };
}
