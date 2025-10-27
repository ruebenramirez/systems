{ config, pkgs, ... }:

let

in
{
  environment.systemPackages = with pkgs; [
    # wine related
    wine
    wine64
    winetricks
    winePackages.fonts
    wineWowPackages.stable
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = false; # Open ports in the firewall for Source Dedicated Server
    localNetworkGameTransfers.openFirewall = false; # Open ports in the firewall for Steam Local Network Game Transfers

    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };
}
