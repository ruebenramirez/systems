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

  # Where the textfile collector looks. node_exporter's own default for this is
  # empty, so the collector does nothing until the flag below spells it out.
  textfileDir = "/var/lib/node_exporter/textfile";

  # amdgpu sysfs counters, written once per timer tick for the textfile
  # collector. Metric names are vendor-neutral on purpose: a host with another
  # vendor's card could emit the same series and inherit the dashboards and the
  # alerts unchanged. nixpkgs ships no AMD GPU exporter to run instead, and
  # sysfs paths are kernel ABI rather than somebody's CLI output format.
  gpuCollector = pkgs.writeShellScript "gpu-metrics" ''
    set -u

    out_dir=${textfileDir}
    tmp="$out_dir/.gpu.prom.tmp"
    trap 'rm -f "$tmp"' EXIT

    # A counter is an integer padded with a newline. One unparsable line discards
    # the whole file, so anything unreadable or non-numeric is dropped, not guessed.
    read_num() {
      [ -r "$1" ] || return 1
      num=$(tr -d '[:space:]' < "$1")
      case "$num" in
        *[!0-9]*) return 1 ;;
      esac
      if [ -z "$num" ]; then
        return 1
      fi
      printf '%s' "$num"
    }

    # Fixed-point divide with three decimals, in shell arithmetic. Bash builtins
    # for the arithmetic on purpose: a systemd unit does not inherit a login
    # shell's PATH, and gawk is not in the one it gets (coreutils and sed are).
    # A tool missing inside $( ) does not fail the unit -- it writes
    # `metric{} ` with an empty value, and one unparsable line costs every GPU
    # metric on the host, not just the one whose tool was missing.
    fixed() {
      printf '%d.%03d' "$(( $1 / $2 ))" "$(( ($1 % $2) * 1000 / $2 ))"
    }

    # Truncate explicitly: the loop below appends, and a surviving .tmp (a run
    # killed between the first printf and the mv) would otherwise be prepended to
    # the next snapshot and duplicate every TYPE line.
    : > "$tmp"
    for family in gpu_utilization_percent gpu_memory_used_bytes gpu_memory_total_bytes \
                  gpu_memory_pool_used_bytes gpu_power_watts gpu_temperature_celsius \
                  gpu_metrics_timestamp_seconds; do
      printf '# TYPE %s gauge\n' "$family" >> "$tmp"
    done

    found=0
    for dev in /sys/class/drm/card*/device; do
      [ -d "$dev" ] || continue
      # The one file that says "this is a GPU we can read"; a card in runtime
      # suspend, or one the driver has not published counters for, is skipped.
      busy=$(read_num "$dev/gpu_busy_percent") || continue
      found=1

      card=$(basename "$(dirname "$dev")")
      pci=$(sed -n 's/^PCI_SLOT_NAME=//p' "$dev/uevent" 2> /dev/null)
      labels="gpu=\"$card\""
      if [ -n "$pci" ]; then
        labels="$labels,pci=\"$pci\""
      fi

      printf 'gpu_utilization_percent{%s} %s\n' "$labels" "$busy" >> "$tmp"

      vram_used=$(read_num "$dev/mem_info_vram_used") || vram_used=0
      vram_total=$(read_num "$dev/mem_info_vram_total") || vram_total=0
      gtt_used=$(read_num "$dev/mem_info_gtt_used") || gtt_used=0
      # The GTT aperture belongs in "total" because on a card whose working set is
      # system memory it dwarfs the on-card figure: fwai0 sets amdgpu.gttsize to
      # give the GPU about 124 GiB of system memory and its mem_info_vram_total is
      # 512 MiB, so VRAM alone would report a card with 14 GiB allocated to it as
      # nearly empty. sysfs exposes the configured aperture, so this picks up the
      # kernel parameter's effect without parsing /proc/cmdline for it.
      gtt_total=$(read_num "$dev/mem_info_gtt_total") || gtt_total=0

      if [ "$vram_total" != 0 ] || [ "$gtt_total" != 0 ]; then
        printf 'gpu_memory_used_bytes{%s} %s\n' "$labels" "$(( vram_used + gtt_used ))" >> "$tmp"
        printf 'gpu_memory_total_bytes{%s} %s\n' "$labels" "$(( vram_total + gtt_total ))" >> "$tmp"
      fi
      # One metric with a pool label, so a single panel shows both pools without
      # two queries stitched together.
      if [ "$vram_total" != 0 ]; then
        printf 'gpu_memory_pool_used_bytes{%s,pool="vram"} %s\n' "$labels" "$vram_used" >> "$tmp"
      fi
      if [ "$gtt_total" != 0 ]; then
        printf 'gpu_memory_pool_used_bytes{%s,pool="gtt"} %s\n' "$labels" "$gtt_used" >> "$tmp"
      fi

      watts=""
      for f in "$dev/power1_average" "$dev/power1_input" \
               "$dev"/hwmon/hwmon*/power1_average "$dev"/hwmon/hwmon*/power1_input; do
        watts=$(read_num "$f") || watts=""
        if [ -n "$watts" ]; then
          break
        fi
      done
      if [ -n "$watts" ]; then
        printf 'gpu_power_watts{%s} %s\n' "$labels" "$(fixed "$watts" 1000000)" >> "$tmp"
      fi

      # Hottest sensor wins: datacenter cards expose an edge and a junction
      # reading, and the junction is the one that trips the throttle.
      temp=""
      for f in "$dev"/hwmon/hwmon*/temp*_input "$dev"/temp*_input; do
        t=$(read_num "$f") || continue
        if [ -z "$temp" ] || [ "$t" -gt "$temp" ]; then
          temp="$t"
        fi
      done
      if [ -n "$temp" ]; then
        printf 'gpu_temperature_celsius{%s} %s\n' "$labels" "$(fixed "$temp" 1000)" >> "$tmp"
      fi

      # Freshness, not presence: the textfile collector serves a stale file
      # forever, so without this a dead timer reads as a frozen GPU.
      printf 'gpu_metrics_timestamp_seconds{%s} %s\n' "$labels" "$(date +%s)" >> "$tmp"
    done

    # No card, no file: an absent series is what GpuMetricsMissing watches for.
    if [ "$found" = 1 ]; then
      # Publish nothing a collector could not parse, for the reason the readers
      # above are strict: one bad line discards the whole file, not just the line.
      dup_types=$(sed -n 's/^# TYPE \([a-z_]*\) .*$/\1/p' "$tmp" | sort | uniq -d)
      if [ -n "$dup_types" ]; then
        printf 'gpu-metrics: duplicate TYPE for %s; not publishing\n' "$dup_types" >&2
        exit 1
      fi
      while IFS= read -r line; do
        case "$line" in
          \#*) continue ;;
        esac
        if ! printf '%s' "$line" | grep -qE '^[a-z_]+\{[^}]*\} [0-9]+(\.[0-9]+)?$'; then
          printf 'gpu-metrics: refusing to publish unparsable line: %s\n' "$line" >&2
          exit 1
        fi
      done < "$tmp"
      chmod 0644 "$tmp"
      mv "$tmp" "$out_dir/gpu.prom"
    fi
  '';
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

    exporters.gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = self.gpu or false;
      description = ''
        Export GPU utilisation, VRAM, power and temperature through the
        node_exporter textfile collector. Defaults to the host's `gpu` flag in
        `nix/lib/inventory.nix`, which is also the label Prometheus uses to hold
        the host to producing those metrics.
      '';
    };

    exporters.gpu.interval = lib.mkOption {
      type = lib.types.str;
      default = "15s";
      example = "30s";
      description = "How often the GPU sysfs snapshot is rewritten (the scrape itself is the fleet's 30s).";
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
      {
        # The GPU metrics ride the node_exporter scrape, so they cannot exist
        # without it; saying so at eval beats an silently empty dashboard row.
        assertion = !cfg.exporters.gpu.enable || cfg.exporters.node.enable;
        message = ''
          my.monitoring.exporters.gpu on ${config.networking.hostName} writes into the
          node_exporter textfile directory, so it needs
          my.monitoring.exporters.node.enable as well.
        '';
      }
      {
        assertion = !cfg.exporters.gpu.enable || (self.gpu or false);
        message = ''
          my.monitoring.exporters.gpu is enabled on ${config.networking.hostName}, which
          the inventory does not mark `gpu = true`. That combination exports
          metrics no alert expects: set the inventory flag or drop the option.
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
      ++ lib.optionals cfg.exporters.gpu.enable [ "textfile" ]
      ++ cfg.exporters.node.extraCollectors;

      extraFlags = lib.optionals cfg.exporters.gpu.enable [
        "--collector.textfile.directory=${textfileDir}"
      ];
    };

    # The writer creates the directory it fills; the exporter only ever reads it.
    # Root-owned with world-readable files is deliberate -- the exporter runs as
    # its own unprivileged user and needs no write access at all.
    systemd.services."gpu-metrics" = lib.mkIf cfg.exporters.gpu.enable {
      description = "Snapshot GPU sysfs counters for the node_exporter textfile collector";
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "node_exporter/textfile";
      };
      script = "${gpuCollector}";
    };

    systemd.timers."gpu-metrics" = lib.mkIf cfg.exporters.gpu.enable {
      description = "Refresh the GPU textfile metrics";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Start well inside GpuMetricsMissing's `for`, so a clean boot never pages.
        OnBootSec = "15s";
        OnUnitActiveSec = cfg.exporters.gpu.interval;
        # The default accuracy is 1min, which would stretch a 15s interval to 1min.
        AccuracySec = "1s";
      };
    };

    networking.firewall.interfaces = lib.listToAttrs (
      map (iface: {
        name = iface;
        value.allowedTCPPorts = [ inventory.nodeExporterPort ];
      }) cfg.allowScrapeFrom
    );
  };
}
