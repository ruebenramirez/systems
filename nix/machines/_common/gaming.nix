{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    moonlight-qt
    winetricks
    wineWowPackages.stable # wine32
    #wineWow64Packages.stable # wine64
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
