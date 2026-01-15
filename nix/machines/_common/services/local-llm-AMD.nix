{ config, pkgs, pkgs-unstable, ... }:
{
  environment.systemPackages = with pkgs-unstable; [
    ollama
  ];

  services.ollama = {
    enable = true;
    acceleration = "vulkan";
    host = "0.0.0.0";
    package = pkgs-unstable.ollama-vulkan;

    environmentVariables = {
      OLLAMA_VULKAN = "1";
      OLLAMA_LLM_LIBRARY = "vulkan";
      GGML_VK_VISIBLE_DEVICES = "0";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q4_0";
      OLLAMA_NUM_PARALLEL = "4";
      OLLAMA_MAX_LOADED_MODELS = "3";
      OLLAMA_KEEP_ALIVE = "-1";
      OLLAMA_NOPREFIX = "1";
      OLLAMA_MAX_QUEUE = "512";
    };
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
