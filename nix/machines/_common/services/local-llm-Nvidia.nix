{ config, pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs-unstable; [
    ollama
  ];

  services.ollama = {
    enable = true;
    acceleration = "cuda";
    host = "0.0.0.0";
    package = pkgs-unstable.ollama;
  };

  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    extraGroups = [ "video" "render" ];
  };

  # allow services access to GPU memory info
  systemd.services.ollama.serviceConfig = {
    AmbientCapabilities = [ "CAP_PERFMON" "CAP_SYS_PTRACE" ];
    CapabilityBoundingSet = [ "CAP_PERFMON" "CAP_SYS_PTRACE" ];
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    openFirewall = true;
    port = 8888;
    package = pkgs-unstable.open-webui;
  };
}
