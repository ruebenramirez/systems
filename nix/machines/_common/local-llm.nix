{ config, pkgs, ... }:

let

in
{

  environment.systemPackages = with pkgs; [
    ollama
  ];

  services.ollama = {
    enable = true;
    acceleration = "cuda";
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = 8888;
  };

}
