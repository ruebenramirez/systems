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

}
