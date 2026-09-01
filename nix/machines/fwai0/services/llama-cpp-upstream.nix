{ lib, config, pkgs, pkgs-unstable, llama-cpp-upstream-vulkan, ... }:

let
  llamaServer = lib.getExe' llama-cpp-upstream-vulkan "llama-server";
in
{
  users.groups.llama-cpp = { };

  users.users.llama-cpp = {
    isSystemUser = true;
    group = "llama-cpp";
    extraGroups = [ "video" "render" ];
    home = "/var/cache/llama-cpp";
  };

  environment.etc."llama-cpp/models.ini".text = ''
    [qwen3.8-27b-mtp]
    model = /models/Qwen3.8-27B-UD-Q4_K_XL.gguf
    alias = qwen3.8-27b-mtp
    ctx-size = 262144
    n-gpu-layers = 999
    flash-attn = on
    cache-type-k = q4_0
    cache-type-v = q4_0
    jinja = true
    cont-batching = true
    spec-type = draft-mtp
    spec-draft-n-max = 3
    spec-draft-p-min = 0.8

    [qwen3.6-35b-a3b-mtp]
    model = /models/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
    alias = qwen3.6-35b-a3b-mtp
    ctx-size = 262144
    n-gpu-layers = 999
    flash-attn = on
    cache-type-k = q4_0
    cache-type-v = q4_0
    jinja = true
    cont-batching = true
    spec-type = draft-mtp
    spec-draft-n-max = 3
    spec-draft-p-min = 0.8

    # [qwen3.8-flash-next]
    # model = /models/Qwen3.8-Flash-Next/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf
    # alias = qwen3.8-flash-next
    # ctx-size = 262144
    # n-gpu-layers = all
    # flash-attn = on
    # cache-type-k = q8_0
    # cache-type-v = q8_0
    # batch-size = 2048
    # ubatch-size = 512
    # parallel = 1
    # fit = off
    # load-mode = mmap
    # lazy-mode = off
    # jinja = true
    # cont-batching = true
    # temp = 1.0
    # top-p = 0.95
    # top-k = 20
    # min-p = 0.0
    # presence-penalty = 0.0
    # repeat-penalty = 1.0
  '';

  systemd.services.llama-cpp = {
    description = "llama.cpp multi-model server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    environment = {
      GGML_VK_VISIBLE_DEVICES = "0";
      HOME = "/var/cache/llama-cpp";
      XDG_CACHE_HOME = "/var/cache/llama-cpp";
    };

    serviceConfig = {
      ExecStart = lib.concatStringsSep " " [
        llamaServer
        "--host 0.0.0.0"
        "--port 8080"
        "--models-preset /etc/llama-cpp/models.ini"
        "--models-max 3"
        "--models-autoload"
      ];

      User = "llama-cpp";
      Group = "llama-cpp";
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

  networking.firewall.allowedTCPPorts = [
    8080
  ];

  environment.systemPackages = [
    llama-cpp-upstream-vulkan
    pkgs-unstable.vulkan-tools
    pkgs-unstable.python3Packages.huggingface-hub
  ];
}
