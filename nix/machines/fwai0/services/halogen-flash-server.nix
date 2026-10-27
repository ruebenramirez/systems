{ pkgs-unstable, ... }:

let
  modelDir = "/home/rramirez/models/halogen";
  # Pinned HF revision of peonist-ai/halogen-qwen3.8-flash-next; carries the
  # native v2 checkpoint and its required lookup table.
  modelRevision = "647e3814953e8435d58f5d5aa13b97aca85a7d93";
  # v2 default (served with HALOGEN_CHECKPOINT unset): self-contained precision,
  # and the layout upstream benchmarks against.
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
    # Both engines are too big to coexist on 128 GiB, so whichever starts stops
    # the other. Only matters if llama-cpp is re-enabled.
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
