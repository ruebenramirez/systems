{ pkgs-unstable, ... }:

let
  modelDir = "/home/rramirez/models/halogen";
  modelRevision = "214a45c7106f515faf3fb72db0cf9a1bf67bfd77";
in
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers.halogen-flash-server = {
      image = "ghcr.io/peonist-ai/halogen-flash-server:0.5.6@sha256:c738212d7ecc5f5288f0dca9173b2d0f0188b9fde94e7ee07f074d71f8152d89";
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
    conflicts = [ "llama-cpp.service" ];
    wants = [ "wg-quick-wg0.service" ];
    after = [ "wg-quick-wg0.service" ];
    unitConfig = {
      AssertPathExists = "${modelDir}/qwen38-flash-next-w4b.hgn";
      RequiresMountsFor = modelDir;
    };
    serviceConfig = {
      LimitMEMLOCK = "infinity";
      RestartSec = "10s";
    };
  };

  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 8731 ];

  # Keep the downloader available for explicit, revision-pinned model updates.
  environment.systemPackages = [ pkgs-unstable.python3Packages.huggingface-hub ];

  environment.etc."halogen/model-revision".text = ''
    ${modelRevision}
  '';
}
