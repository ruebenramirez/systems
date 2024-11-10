{ config, pkgs, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    ollama
  ];

  services.ollama = {
    acceleration = "cuda";
    enable = true;
    listenAddress = "0.0.0.0";
  };

  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = 8888;
  };
}
