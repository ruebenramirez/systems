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
  # An option (not a let constant) so other collectors writing into the same
  # directory take the path from here instead of duplicating it.
  textfileDir = cfg.textfileDir;

  # Several collectors write into that one directory, so the textfile collector is
  # enabled if any of them is.
  textfileEnabled =
    cfg.exporters.textfile.enable || cfg.exporters.gpu.enable || cfg.exporters.model.enable;

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

  # What the model server holds in RAM is invisible to every other metric on this
  # host: its weights are file-cache pages, so free(1) books them as reclaimable
  # and the GPU maps only a window of them (see gpu_memory_pool_used_bytes). The
  # one place residency is visible is the process's own address space, so that is
  # what gets read here. NVMe health rides along because both answer the same
  # question: is the model in RAM, and what does the drive do when it is not.
  modelCollector = pkgs.writeShellScript "model-metrics" ''
    set -u

    out_dir=${textfileDir}
    container=${cfg.exporters.model.container}
    device=${cfg.exporters.model.device}
    checkpoint_pattern=${lib.escapeShellArg cfg.exporters.model.checkpointPattern}
    table_pattern=${lib.escapeShellArg cfg.exporters.model.tablePattern}
    pgrep_tool=${pkgs.procps}/bin/pgrep
    smartctl=${pkgs.smartmontools}/sbin/smartctl
    jq_bin=${pkgs.jq}/bin/jq
    podman=${pkgs.podman}/bin/podman
    tmp="$out_dir/.model.prom.tmp"
    trap 'rm -f "$tmp"' EXIT

    # Truncate explicitly, for the reason the GPU collector spells out: everything
    # below appends, and `trap ... EXIT` does not run on the SIGTERM a
    # `systemctl stop` during a switch sends, so a surviving tmp would be appended
    # to and every later publish would fail the duplicate-TYPE gate below.
    : > "$tmp"

    for family in halogen_weights_mapped_bytes halogen_weights_resident_bytes \
                  halogen_table_mapped_bytes halogen_table_resident_bytes \
                  halogen_rss_bytes halogen_mlocked_bytes \
                  halogen_table_lookup_seconds halogen_process_start_seconds \
                  nvme_percentage_used nvme_available_spare_percent \
                  nvme_temperature_celsius nvme_smart_status_passed \
                  model_metrics_timestamp_seconds; do
      printf '# TYPE %s gauge\n' "$family" >> "$tmp"
    done
    # Counters rather than gauges: the NVMe values only ever grow over the drive's
    # life, and major faults over the process's.
    for family in halogen_major_faults_total nvme_media_errors_total \
                  nvme_unsafe_shutdowns_total nvme_data_units_written_bytes \
                  nvme_data_units_read_bytes; do
      printf '# TYPE %s counter\n' "$family" >> "$tmp"
    done

    # Every sample carries a label set, because the gate at the end demands one and
    # one unparsable line costs every metric in the file rather than its own.
    emit() {
      printf '%s{%s} %s\n' "$1" "$2" "$3" >> "$tmp"
    }

    good() {
      case "$1" in
        *[!0-9]*) return 1 ;;
      esac
      if [ -n "$1" ]; then
        return 0
      fi
      return 1
    }

    engine='engine="flash_serve"'
    devbase=$(basename "$device")
    dev_label=$(printf 'device="%s"' "$devbase")

    # -o takes the oldest match, so a stale duplicate cannot become the measured
    # process: exactly one sample per host is what the alerts' gate joins need.
    engine_found=0
    pid=$($pgrep_tool -o -x flash_serve)
    if [ -n "$pid" ] && [ -r "/proc/$pid/smaps" ]; then
      engine_found=1
      # Size is what the engine mapped, Rss what is resident; Rss below Size means
      # the remainder is being read off the drive again. One walk of smaps for both
      # files rather than one per field: reading this address space costs ~0.7s of
      # system time on fwai0 and runs under mmap_lock beside live inference, so the
      # four walks were most of a 6s tick. Both model files map exactly once, so
      # attribution is a label carried across the handful of grep -A4 lines.
      cur=""
      w_size=0
      w_rss=0
      t_size=0
      t_rss=0
      while IFS= read -r line; do
        n=""
        case "$line" in
          *"$checkpoint_pattern") cur="w" ;;
          *"$table_pattern") cur="t" ;;
          Size:*|Rss:*) n=$(printf '%s' "$line" | tr -s ' ' | cut -d' ' -f2) ;;
        esac
        if good "$n"; then
          bytes=$(( n * 1024 ))
          if [ "$cur" = "w" ]; then
            case "$line" in
              Size:*) w_size=$(( w_size + bytes )) ;;
              Rss:*) w_rss=$(( w_rss + bytes )) ;;
            esac
          else
            case "$line" in
              Size:*) t_size=$(( t_size + bytes )) ;;
              Rss:*) t_rss=$(( t_rss + bytes )) ;;
            esac
          fi
        fi
      done < <(grep -A4 -- "$checkpoint_pattern\|$table_pattern" "/proc/$pid/smaps")
      rss=$(sed -n 's/^Rss:[[:space:]]*\([0-9]*\).*/\1/p' "/proc/$pid/smaps_rollup")
      locked=$(sed -n 's/^Locked:[[:space:]]*\([0-9]*\).*/\1/p' "/proc/$pid/smaps_rollup")
      # Field 12 of stat, but the comm field can hold spaces and parentheses, so
      # cut up to the closing paren first: after it, the original field N sits at
      # N-1.
      majflt=$(cut -d')' -f2- "/proc/$pid/stat" | tr -s ' ' | cut -d' ' -f11)
      # starttime is field 22 of stat (f21 after the comm paren) in clock ticks
      # since boot; USER_HZ is 100 on every Linux arch in this fleet. The alerts
      # use it to tell a cold page cache from an evicted one.
      start_ticks=$(cut -d')' -f2- "/proc/$pid/stat" | tr -s ' ' | cut -d' ' -f21)
      btime=$(sed -n 's/^btime //p' /proc/stat)
      if good "$start_ticks" && good "$btime"; then
        emit halogen_process_start_seconds "$engine" "$(( btime + start_ticks / 100 ))"
      fi

      if [ "$w_size" -gt 0 ]; then
        emit halogen_weights_mapped_bytes "$engine" "$w_size"
        emit halogen_weights_resident_bytes "$engine" "$w_rss"
      fi
      if [ "$t_size" -gt 0 ]; then
        emit halogen_table_mapped_bytes "$engine" "$t_size"
        emit halogen_table_resident_bytes "$engine" "$t_rss"
      fi
      if good "$rss"; then
        emit halogen_rss_bytes "$engine" "$(( rss * 1024 ))"
      fi
      # Nonzero here is the proof HALOGEN_WEIGHTS_LOCK took effect; zero means the
      # weights are reclaimable file cache and HalogenWeightsLockInactive says so.
      if good "$locked"; then
        emit halogen_mlocked_bytes "$engine" "$(( locked * 1024 ))"
      fi
      if good "$majflt"; then
        emit halogen_major_faults_total "$engine" "$majflt"
      fi

      # The engine times its own lookup-table reads and logs one whenever it takes
      # two seconds or more, so the absence of this series is the good state. The
      # value is the worst read in the window, not the last: the one that hurts is
      # the one worth alerting on.
      look=$(timeout 30 "$podman" logs --since 15m "$container" 2>&1 \
        | grep -oE 'lookup table: .* took [0-9]+\.[0-9]+ s' \
        | sed 's/.*took \([0-9.]*\) s$/\1/' \
        | sort -g | tail -n 1)
      if [ -n "$look" ]; then
        emit halogen_table_lookup_seconds "$engine" "$look"
      fi
    fi

    # smartctl's own JSON. Its text layout is not a contract and its `-l` names
    # have changed between versions (`-l nvm-smart` is not one on 7.5), so the
    # health log is read from the fields rather than aligned columns; jq is named
    # outright rather than found on PATH, which a unit's does not carry.
    json=$(timeout 30 "$smartctl" -j -a "$device" 2>/dev/null)
    smart_get() {
      printf '%s' "$json" | "$jq_bin" -r "($1) // empty" 2>/dev/null
    }

    # power_on_hours is deliberately not exported: this firmware has been seen to
    # report it far under real uptime, so anything scheduled from it would be wrong.
    # Three-way, not if/else: smartctl answers a device it cannot open with valid
    # JSON that has no smart_status at all, and jq reads an absent field as null --
    # falsy -- so `if ... then 1 else 0 end` emits a passing 0 for "no answer" and
    # NvmeSmartStatusFailed pages a healthy drive. Absent means empty: the fail-closed
    # gate below then refuses to publish and NvmeMetricsMissing says what is missing.
    passed=$(smart_get 'if .smart_status.passed == true then 1 elif .smart_status.passed == false then 0 else empty end')
    if [ -n "$passed" ]; then
      emit nvme_smart_status_passed "$dev_label" "$passed"
    fi

    log='.nvme_smart_health_information_log'
    for pair in "nvme_percentage_used percentage_used" \
                "nvme_available_spare_percent available_spare" \
                "nvme_media_errors_total media_errors" \
                "nvme_unsafe_shutdowns_total unsafe_shutdowns" \
                "nvme_temperature_celsius temperature"; do
      name=$(printf '%s' "$pair" | cut -d' ' -f1)
      val=$(smart_get "$log.$(printf '%s' "$pair" | cut -d' ' -f2)")
      if [ -n "$val" ]; then
        emit "$name" "$dev_label" "$val"
      fi
    done

    # Data units are counted in thousands of 512-byte blocks; the arithmetic stays
    # in the shell so the byte counts never pass through a float.
    for pair in "nvme_data_units_written_bytes data_units_written" \
                "nvme_data_units_read_bytes data_units_read"; do
      name=$(printf '%s' "$pair" | cut -d' ' -f1)
      val=$(smart_get "$log.$(printf '%s' "$pair" | cut -d' ' -f2)")
      if [ -n "$val" ]; then
        emit "$name" "$dev_label" "$(( val * 512000 ))"
      fi
    done

    # Freshness, not presence: the textfile collector serves a stale file forever.
    emit model_metrics_timestamp_seconds 'scope="collector"' "$(date +%s)"

    # Fail closed on absence too, not just on garbage. A renamed checkpoint (a
    # modelRevision bump) or a smartctl that stops answering drops whole families
    # through the guards above, the file still parses, and the alerts those families
    # feed go silently green while the host looks fully instrumented. Absence of the
    # engine itself is not one of these: then the timestamp-only file is what should
    # publish, so ModelMetricsMissing rather than ModelCollectionStale is what pages.
    missing=""
    if [ "$engine_found" = 1 ]; then
      if [ "$w_size" -eq 0 ]; then
        missing="$missing halogen_weights_*"
      fi
      if [ "$t_size" -eq 0 ]; then
        missing="$missing halogen_table_*"
      fi
    fi
    if ! grep -q '^nvme_smart_status_passed{' "$tmp"; then
      missing="$missing nvme_*"
    fi
    if [ -n "$missing" ]; then
      printf 'model-metrics: not publishing, no sample for%s\n' "$missing" >&2
      exit 1
    fi

    dup_types=$(sed -n 's/^# TYPE \([a-z_]*\) .*$/\1/p' "$tmp" | sort | uniq -d)
    if [ -n "$dup_types" ]; then
      printf 'model-metrics: duplicate TYPE for %s; not publishing\n' "$dup_types" >&2
      exit 1
    fi
    while IFS= read -r line; do
      case "$line" in
        \#*) continue ;;
      esac
      if ! printf '%s' "$line" | grep -qE '^[a-z_]+\{[^}]*\} [0-9]+(\.[0-9]+)?$'; then
        printf 'model-metrics: refusing to publish unparsable line: %s\n' "$line" >&2
        exit 1
      fi
    done < "$tmp"
    chmod 0644 "$tmp"
    mv "$tmp" "$out_dir/model.prom"
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

    textfileDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/node_exporter/textfile";
      description = "Directory the textfile collector reads; other collectors writing .prom files take the path from here.";
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

    exporters.textfile.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the textfile collector without turning on a specific collector
        (gpu/model imply it themselves). A host that writes its own .prom files
        through another module sets this.
      '';
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

    exporters.model.enable = lib.mkOption {
      type = lib.types.bool;
      default = self.llm or false;
      description = ''
        Export the model server's resident checkpoint and lookup-table bytes and
        the NVMe health log through the node_exporter textfile collector.
        Defaults to the host's `llm` flag in `nix/lib/inventory.nix`, which is
        also the label Prometheus uses to hold the host to producing them.
      '';
    };

    exporters.model.interval = lib.mkOption {
      type = lib.types.str;
      default = "30s";
      example = "60s";
      description = "How often the model and NVMe snapshot is rewritten.";
    };

    exporters.model.container = lib.mkOption {
      type = lib.types.str;
      default = "halogen-flash-server";
      description = "Container whose log carries the engine's own lookup-table timings.";
    };

    exporters.model.device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/nvme0";
      description = "Namespace device whose NVMe health log is exported.";
    };

    exporters.model.checkpointPattern = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "qwen38-flash-next-v2.hgn";
      description = ''
        Substring identifying the checkpoint mapping in /proc/<pid>/smaps. Set it
        from the same string as the container's model file, so a model revision
        bump cannot leave the collector counting bytes for a file that no longer
        exists. No default: guessing here silently drops the residency metrics.
      '';
    };

    exporters.model.tablePattern = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "qwen38-flash-next-ngram.hgn";
      description = ''
        Substring identifying the lookup-table mapping in /proc/<pid>/smaps.
        See `checkpointPattern`.
      '';
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
      {
        assertion = !cfg.exporters.model.enable || cfg.exporters.node.enable;
        message = ''
          my.monitoring.exporters.model on ${config.networking.hostName} writes into the
          node_exporter textfile directory, so it needs
          my.monitoring.exporters.node.enable as well.
        '';
      }
      {
        assertion = !cfg.exporters.model.enable || (self.llm or false);
        message = ''
          my.monitoring.exporters.model is enabled on ${config.networking.hostName},
          which the inventory does not mark `llm = true`. That combination exports
          metrics no alert expects: set the inventory flag or drop the option.
        '';
      }
      {
        assertion =
          !cfg.exporters.model.enable
          || (cfg.exporters.model.checkpointPattern != "" && cfg.exporters.model.tablePattern != "");
        message = ''
          my.monitoring.exporters.model on ${config.networking.hostName} needs both
          checkpointPattern and tablePattern: they are what the collector matches in
          /proc/<pid>/smaps, so without them it publishes no residency metrics at all
          and every alert that reads them is off. Set them next to the container
          definition, from the same strings it uses for the model files.
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
      ++ lib.optionals textfileEnabled [ "textfile" ]
      ++ cfg.exporters.node.extraCollectors;

      extraFlags = lib.optionals textfileEnabled [
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

    # Runs as root, which both halves need: /proc/<pid>/smaps of the engine's
    # process is not world-readable, and the NVMe health log is an admin command.
    systemd.services."model-metrics" = lib.mkIf cfg.exporters.model.enable {
      description = "Snapshot model-server residency and NVMe health for the textfile collector";
      serviceConfig = {
        Type = "oneshot";
        StateDirectory = "node_exporter/textfile";
      };
      script = "${modelCollector}";
    };

    systemd.timers."model-metrics" = lib.mkIf cfg.exporters.model.enable {
      description = "Refresh the model and NVMe textfile metrics";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = cfg.exporters.model.interval;
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
