{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.monitoring;
  inventory = import ../../lib/inventory.nix;
  self = inventory.hosts.${config.networking.hostName} or { };
in
{
  options.my.monitoring = {
    # Importing this module is the opt-in, so it defaults on; a host that must
    # not export metrics sets my.monitoring.enable = false (or drops the import).
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prometheus exporters for fleet-wide monitoring.";
    };

    exporters.node.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run node_exporter (CPU, memory, disk, systemd state).";
    };

    exporters.node.extraCollectors = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "textfile" ];
      description = "Extra node_exporter collectors beyond systemd (plus zfs where the host has a pool).";
    };

    # Reachable-by list for the scrape firewall rule. The fleet's Prometheus
    # runs in the k3s cluster, whose pod egress is masqueraded to the node's
    # tailnet address, so the tailnet interface is the only thing that ever
    # needs to be allowed in.
    allowScrapeFrom = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "tailscale0" ];
      description = "Firewall interfaces allowed to reach the exporters.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.elem config.networking.hostName inventory.monitoredHosts;
        message = ''
          my.monitoring is enabled on ${config.networking.hostName}, which is not a
          monitored host in nix/lib/inventory.nix. Either import it there or drop
          the module here -- the fleet inventory and the flake must agree.
        '';
      }
    ];

    services.prometheus.exporters.node = lib.mkIf cfg.exporters.node.enable {
      enable = true;
      openFirewall = false;
      listenAddress = "0.0.0.0";
      enabledCollectors = [
        "systemd"
      ]
      ++ lib.optional (self.zfs or false) "zfs"
      ++ cfg.exporters.node.extraCollectors;
    };

    networking.firewall.interfaces = lib.listToAttrs (
      map (iface: {
        name = iface;
        value.allowedTCPPorts = [ inventory.nodeExporterPort ];
      }) cfg.allowScrapeFrom
    );
  };
}
