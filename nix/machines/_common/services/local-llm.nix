{ config, pkgs, pkgs-unstable, ... }:

let

in
{

  environment.systemPackages = with pkgs-unstable; [
    pkgs-unstable.ollama
  ];

  services.ollama = {
    acceleration = "rocm"; # default to rocm (((((((((and override on nvidia machines)
    enable = true;
    host = "0.0.0.0";
    package = pkgs-unstable.ollama;
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
    port = 8888;
    package = pkgs.open-webui;
  };
}
