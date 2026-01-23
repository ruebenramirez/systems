{ config, pkgs, pkgs-unstable, ... }:
{
  services.ollama = {
    enable = true;
    acceleration = "vulkan";
    host = "0.0.0.0";
    package = pkgs-unstable.ollama-vulkan;

    environmentVariables = {
      # Backend Selection
      OLLAMA_VULKAN = "1";
      OLLAMA_LLM_LIBRARY = "vulkan";
      GGML_VK_VISIBLE_DEVICES = "0";

      # Performance & Reasoning
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q4_0";
      OLLAMA_NUM_PARALLEL = "4";

      # Memory Management (128GB GTT Optimization)
      OLLAMA_NUM_CTX = "32768";         # 32k context window
      OLLAMA_MAX_LOADED_MODELS = "3";
      OLLAMA_KEEP_ALIVE = "-1";
      OLLAMA_NOPREFIX = "1";
      OLLAMA_MAX_QUEUE = "512";
      OLLAMA_CONTEXT_LENGTH = "32768";
    };
  };
  networking.firewall.allowedTCPPorts = [
    11434 # ollama
  ];

  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
    extraGroups = [ "video" "render" ];

  };
  users.groups.ollama = {};

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



  environment.systemPackages = with pkgs; [
    llama-cpp-rocm # model file manipulation
    #llama-cpp-vulkan
    python3Packages.huggingface-hub # for huggingface-cli
  ];
}
