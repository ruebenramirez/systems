{ pkgs-unstable, ... }:

let
  modelDir = "/home/rramirez/models/halogen";
  # Pinned Hugging Face revision of peonist-ai/halogen-qwen3.8-flash-next.
  # 647e3814 is the current main and carries the native v2 checkpoint
  # (qwen38-flash-next-v2.hgn) plus its required lookup table
  # (qwen38-flash-next-ngram.hgn).
  modelRevision = "647e3814953e8435d58f5d5aa13b97aca85a7d93";
  # Native v2 checkpoint: the 0.15+ default, served with HALOGEN_CHECKPOINT
  # unset. It is a single file that carries its own precision (no sidecar to
  # keep in sync) and is the configuration every upstream perf/quality number
  # is measured against -- the most stable, best-supported layout.
  checkpoint = "qwen38-flash-next-v2.hgn";
  lookupTable = "qwen38-flash-next-ngram.hgn";
in
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers.halogen-flash-server = {
      image = "ghcr.io/peonist-ai/halogen-flash-server:0.18.14@sha256:e0c1d1b48e07c8acdd204fbdbafbb421a395a73cf704271845a1846ad1fd767f";
      pull = "missing";
      environment = {
        HALOGEN_KV_POOL_POSITIONS = "262144";
        HALOGEN_MAX_TOK = "8192";
      };
      volumes = [ "${modelDir}:/models:ro" ];
      devices = [
        "/dev/kfd:/dev/kfd"
        "/dev/dri:/dev/dri"
      ];
      networks = [ "host" ];
      podman.sdnotify = "healthy";
      extraOptions = [
        "--health-cmd=/usr/local/bin/halogen-healthcheck auto"
        "--health-interval=30s"
        "--health-on-failure=kill"
        "--health-retries=3"
        "--health-start-period=45m"
        "--health-timeout=35s"
        "--ipc=host"
        "--ulimit=memlock=-1:-1"
      ];
    };
  };

  systemd.services.podman-halogen-flash-server = {
    # Mutual exclusion with the llama.cpp server (llama-cpp-upstream.nix, now
    # disabled in configuration.nix). Both are memory-heavy inference engines
    # and cannot coexist on this 128 GiB box -- halogen needs ~62 GiB pinned
    # plus a 16 GiB floor -- so whichever starts must stop the other. Harmless
    # while llama-cpp.service does not exist; it only bites if that module is
    # re-enabled, which is exactly when the interlock is wanted.
    conflicts = [ "llama-cpp.service" ];
    wants = [ "tailscaled-autoconnect.service" ];
    after = [ "tailscaled-autoconnect.service" ];
    unitConfig = {
      # v2 needs both the checkpoint and its lookup table present.
      AssertPathExists = [
        "${modelDir}/${checkpoint}"
        "${modelDir}/${lookupTable}"
      ];
      RequiresMountsFor = modelDir;
    };
    serviceConfig = {
      LimitMEMLOCK = "infinity";
      RestartSec = "10s";
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8731 ];

  # Keep the downloader available for explicit, revision-pinned model updates.
  environment.systemPackages = [ pkgs-unstable.python3Packages.huggingface-hub ];

  environment.etc."halogen/model-revision".text = ''
    ${modelRevision}
  '';
}
