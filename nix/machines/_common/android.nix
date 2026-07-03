{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    android-tools
    # android-studio
    # android-studio-tools
    android-file-transfer
  ];
}
