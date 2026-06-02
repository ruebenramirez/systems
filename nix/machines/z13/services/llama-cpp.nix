{ lib, config, pkgs, pkgs-unstable, ... }:

let
  modelFile = "Qwen3.6-27B-UD-Q4_K_XL.gguf";
in
{
  services.llama-cpp = {
    enable = true;
    package = pkgs-unstable.llama-cpp-vulkan;

    model = "/models/${modelFile}";
    host = "0.0.0.0";
    port = 8080;
    openFirewall = true;

    extraFlags = [
      "--jinja"
      "--n-gpu-layers" "999"
      "--ctx-size" "131072"
      "--flash-attn" "on"
      "--cache-type-k" "q4_0"
      "--cache-type-v" "q4_0"
      "--spec-type" "draft-mtp"
      "--spec-draft-n-max" "2"
      "--cont-batching"
    ];
  };

  systemd.services.llama-cpp = {
    environment = {
      GGML_VK_VISIBLE_DEVICES = "0";
      HOME = "/var/cache/llama-cpp";
      XDG_CACHE_HOME = "/var/cache/llama-cpp";
    };

    serviceConfig = {
      SupplementaryGroups = [ "video" "render" ];

      CacheDirectory = "llama-cpp";
      StateDirectory = "llama-cpp";

      BindReadOnlyPaths = [
        "/home/rramirez/models:/models"
      ];

      AmbientCapabilities = [ "CAP_PERFMON" "CAP_SYS_PTRACE" ];
      CapabilityBoundingSet = [ "CAP_PERFMON" "CAP_SYS_PTRACE" ];
    };
  };

  environment.systemPackages = with pkgs-unstable; [
    llama-cpp-vulkan
    vulkan-tools
    python3Packages.huggingface-hub
  ];
}
