{ config, pkgs, pkgs-unstable, ... }:

let

in
{

  environment.systemPackages = with pkgs-unstable; [
    pkgs-unstable.ollama
  ];

  services.ollama = {
    acceleration = "cuda";
    enable = true;
    host = "0.0.0.0";
    package = pkgs-unstable.ollama;
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = 8888;
    package = pkgs-unstable.open-webui;
  };
}
