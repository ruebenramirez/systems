# Prometheus scrape configuration and alert rules, generated from the fleet
# inventory. Everything here is derived: adding a service to
# nix/lib/inventory.nix adds its scrape job and its "is it down" alert.
{ inventory }:
let
  # Scrape jobs for node_exporter on every monitored host. Written as
  # prometheus `static_configs`, because these hosts are outside the cluster
  # and have no ServiceMonitor to discover.
  scrapeConfigs = [
    {
      job_name = "fleet-node-exporters";
      honor_labels = true;
      scrape_interval = "30s";
      scrape_timeout = "15s";
      static_configs = inventory.nodeScrapeTargets;
      metric_relabel_configs = [
        # Noisy and useless at fleet scale: per-CPU frequency states and the
        # netdev stats of virtual/tunnel interfaces.
        {
          source_labels = [ "__name__" ];
          regex = "node_cpu_frequency_hertz|node_cpu_scaling_.*|node_hwmon_.*";
          action = "drop";
        }
      ];
    }
  ]
  ++ (builtins.attrValues (
    builtins.mapAttrs (module: targets: {
      job_name = "blackbox-${module}";
      metrics_path = "/probe";
      scrape_interval = "60s";
      scrape_timeout = "15s";
      params = {
        module = [ module ];
      };
      # inventory groups probes as static-config entries ({targets,labels});
      # they have to sit under static_configs, not at job level.
      static_configs = targets;
      relabel_configs = [
        {
          source_labels = [ "__address__" ];
          target_label = "__param_target";
        }
        {
          source_labels = [ "__param_target" ];
          target_label = "instance";
        }
        {
          target_label = "__address__";
          replacement = "blackbox-exporter.monitoring.svc.cluster.local:9110";
        }
      ];
    }) inventory.probeTargetsByModule
  ));

  # The alert set: one alert per failure mode worth being woken for, plus the
  # predictions that turn a slow problem into an early warning.
  rules = {
    groups = [
      {
        name = "fleet-hosts";
        rules = [
          {
            alert = "HostDown";
            expr = ''up{job="fleet-node-exporters"} == 0'';
            for = "2m";
            labels = {
              severity = "critical";
              tier = "host";
            };
            annotations = {
              summary = "Instance {{ $labels.instance }} is not scraping";
              description = "node_exporter on {{ $labels.instance }} has been unreachable for 2 minutes. Everything else on this host is unverifiable until it is back.";
            };
          }
          {
            alert = "HostCpuSustainedHigh";
            expr = ''
              (1 - avg by (instance, host) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 90
            '';
            for = "15m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "CPU above 90% on {{ $labels.instance }} for 15m";
              description = "CPU has been saturated for 15 minutes; check what is running before it turns into queued work.";
            };
          }
          {
            alert = "HostMemoryPressure";
            # ZFS hosts deliberately fill RAM with the ARC, which /proc/meminfo
            # does not count as available even though it is reclaimed on demand.
            # So the raw ratio is only the truth once: the `unless` drops the
            # alert wherever adding the ARC back restores headroom, and on
            # non-ZFS hosts (no node_zfs_arc_size) the join yields nothing and
            # the plain reading stands.
            expr = ''
              (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.10)
              unless on (host)
              ((node_memory_MemAvailable_bytes + node_zfs_arc_size) / node_memory_MemTotal_bytes >= 0.10)
            '';
            for = "15m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Less than 10% memory available on {{ $labels.instance }}";
              description = "Sustained memory pressure (ZFS ARC counted as reclaimable); the OOM killer is the next event on this host.";
            };
          }
          {
            alert = "HostSwapThrashing";
            expr = ''
              rate(node_vmstat_pswpin[5m]) * 4 + rate(node_vmstat_pswpout[5m]) * 4 > 1000
            '';
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} is swapping heavily";
              description = "More than 1000 pages/s of swap traffic; memory demand exceeds the box.";
            };
          }
          {
            alert = "HostDiskSpaceLow";
            expr = ''
              node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|vfat|overlay|autofs"}
                / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|vfat|overlay|autofs"} < 0.15
            '';
            for = "30m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Under 15% free on {{ $labels.instance }} {{ $labels.mountpoint }}";
              description = "Filesystem {{ $labels.mountpoint }} ({{ $labels.device }}) is filling up.";
            };
          }
          {
            # The expensive one: ENOSPC discovered by a writer, not a dashboard.
            alert = "HostDiskPredictedFull";
            expr = ''
              predict_linear(node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|vfat|overlay|autofs"}[6h], 4 * 3600) < 0
            '';
            for = "15m";
            labels = {
              severity = "critical";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} {{ $labels.mountpoint }} predicted full within 4h";
              description = "The last 6 hours of write rate, extrapolated 4 hours forward, runs out of space on {{ $labels.mountpoint }}.";
            };
          }
          {
            alert = "HostInodesLow";
            expr = ''
              node_filesystem_files_free{fstype!~"tmpfs|ramfs|overlay"}
                / node_filesystem_files{fstype!~"tmpfs|ramfs|overlay"} < 0.10
            '';
            for = "30m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Under 10% inodes free on {{ $labels.instance }} {{ $labels.mountpoint }}";
              description = "A filesystem can be 'full' with bytes to spare; this is that failure.";
            };
          }
          {
            alert = "HostDiskIOSaturated";
            expr = "rate(node_disk_io_time_seconds_total[5m]) > 0.9";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} device {{ $labels.device }} is I/O saturated";
              description = "The device spent >90% of the last 5 minutes doing I/O; latency, not capacity.";
            };
          }
          {
            alert = "HostNetworkErrors";
            expr = ''
              increase(node_network_receive_errs_total[10m]) > 10
                or increase(node_network_transmit_errs_total[10m]) > 10
            '';
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "NIC errors on {{ $labels.instance }} {{ $labels.device }}";
              description = "Physical-layer or driver errors on an interface; usually a cable, a NIC, or a bad switch port.";
            };
          }
          {
            alert = "HostClockDrift";
            expr = "abs(node_timex_offset_seconds) > 0.05";
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Clock drift above 50ms on {{ $labels.instance }}";
              description = "NTP is not holding the clock; certificate validation, log ordering and etcd all get worse from here.";
            };
          }
          {
            alert = "HostClockNotSynchronised";
            expr = "node_timex_sync_status == 0";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "No time synchronisation on {{ $labels.instance }}";
              description = "Time sync has stopped; drift is now unbounded.";
            };
          }
          {
            alert = "SystemdUnitFailed";
            expr = ''node_systemd_unit_state{state="failed"} == 1'';
            for = "5m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Unit {{ $labels.name }} is failed on {{ $labels.instance }}";
              description = "systemd gave up on this unit. `systemctl status {{ $labels.name }}` on {{ $labels.instance }}.";
            };
          }
          # Disk health arrives through the textfile collector on the hosts the
          # inventory marks `smart = true` (see
          # nix/machines/_common/monitoring.nix). The collector fails closed: it
          # publishes nothing when no device answers, so an absent series always
          # means "telemetry gone" and never "all disks fine".
          {
            alert = "SmartMetricsMissing";
            expr = ''
              (up{job="fleet-node-exporters", smart="true"} == 1)
                unless on (host, instance) (smart_status_passed)
            '';
            for = "30m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "No SMART metrics from {{ $labels.instance }}";
              description = "{{ $labels.host }} is scraping but reports no disk health, so reallocated sectors, pending sectors and disk temperature are unmonitored there; smartmontools is missing, smartctl stopped answering, or no device passed a SMART status.";
            };
          }
          {
            alert = "SmartCollectionStale";
            expr = "time() - smart_collection_timestamp_seconds > 1800";
            for = "20m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "SMART metrics from {{ $labels.instance }} have not updated in 30 minutes";
              description = "smart-metrics.timer is not refreshing the textfile, so the disk health numbers for {{ $labels.host }} are frozen rather than missing; a drive can degrade past a frozen snapshot without tripping any of the SMART alerts.";
            };
          }
          {
            # USB shelves in a chassis with everything else have no airflow of
            # their own, which is the situation tank is in.
            alert = "SmartDiskTemperatureHigh";
            expr = "smart_temperature_celsius > 55";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.host }} disk {{ $labels.device }} running hot at {{ $value }}C";
              description = "{{ $labels.device }} on {{ $labels.host }} has been above 55C for 15 minutes. Spindle life falls quickly past this and the failure is usually permanent rather than intermittent.";
            };
          }
        ];
      }

      # GPU telemetry arrives through the textfile collector on the hosts the
      # inventory marks `gpu = true` (see
      # nix/machines/_common/monitoring.nix). Utilisation and VRAM are
      # deliberately not alerted on: on fwai0 pinning the card's memory and
      # sitting at 100% is the workload succeeding, not failing.
      {
        name = "fleet-gpu";
        rules = [
          {
            # The scrape target carries gpu="true" from the inventory, so this is
            # "a host that must export GPU metrics and is not": card gone, sysfs
            # layout changed, collector never installed.
            alert = "GpuMetricsMissing";
            expr = ''
              (up{job="fleet-node-exporters", gpu="true"} == 1)
                unless on (host, instance) (gpu_utilization_percent)
            '';
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "No GPU metrics from {{ $labels.instance }}";
              description = "{{ $labels.host }} is scraping and is supposed to have a GPU, but exports no gpu_* metrics; the GPU row on its dashboard is blind.";
            };
          }
          {
            # The textfile collector keeps serving the last file written, so a
            # dead timer freezes the numbers instead of losing them. The collector
            # writes the time it read sysfs to make that visible.
            alert = "GpuCollectionStale";
            expr = "time() - gpu_metrics_timestamp_seconds > 120";
            for = "5m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "GPU metrics from {{ $labels.instance }} have not updated in 2 minutes";
              description = "gpu-metrics.timer is not refreshing the textfile, so every GPU number for {{ $labels.host }} is a frozen old reading rather than a missing one.";
            };
          }
          {
            # Junction temperature, which is what throttles: the collector reports
            # the hottest sensor the card exposes.
            alert = "GpuThermalLimit";
            expr = "gpu_temperature_celsius > 95";
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} {{ $labels.gpu }} at {{ $value }}C for 10m";
              description = "A card this hot is throttling or about to; check dust, fan curves and case airflow on {{ $labels.host }}.";
            };
          }
        ];
      }

      # Model-server residency and drive health, from the textfile collector on
      # hosts the inventory marks `llm = true`. These exist because the standard
      # metrics cannot answer the one question that matters on an inference host:
      # is the checkpoint in RAM or is it being read off the drive again. The
      # weights are file-cache pages, so free(1) and node_exporter both book them
      # as reclaimable cache, and the GPU only ever maps a window of them.
      {
        name = "fleet-llm";
        rules = [
          {
            alert = "ModelMetricsMissing";
            # Keyed on the checkpoint mapping rather than halogen_rss_bytes: rss is
            # exported whenever a process named flash_serve exists, so it stays green
            # when a renamed model file leaves only the residency families missing.
            expr = ''
              (up{job="fleet-node-exporters", llm="true"} == 1)
                unless on (host, instance) (halogen_weights_mapped_bytes)
            '';
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "No model residency metrics from {{ $labels.instance }}";
              description = "{{ $labels.host }} is scraping and is supposed to serve the model, but exports no checkpoint mapping: either the engine is not running or its model files were renamed out from under the collector's pattern.";
            };
          }
          {
            alert = "ModelCollectionStale";
            expr = "time() - model_metrics_timestamp_seconds > 120";
            for = "5m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Model metrics from {{ $labels.instance }} have not updated in 2 minutes";
              description = "model-metrics.timer is not refreshing the textfile, so the residency numbers for {{ $labels.host }} are frozen rather than missing.";
            };
          }
          {
            # The drive-health mirror of ModelMetricsMissing: smartctl going quiet
            # takes three alerts out at once while every halogen_* series keeps
            # looking healthy.
            alert = "NvmeMetricsMissing";
            expr = ''
              (up{job="fleet-node-exporters", llm="true"} == 1)
                unless on (host, instance) (nvme_smart_status_passed)
            '';
            for = "15m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "No NVMe health metrics from {{ $labels.instance }}";
              description = "{{ $labels.host }} is scraping but reports no drive health, so endurance, spare blocks and media errors are unmonitored there; smartctl stopped answering or the device path moved.";
            };
          }
          {
            # The residency alerts below match their cold-boot gates on
            # (host, instance), so a missing gate input does not raise an error, it
            # silently disarms them: the host still exports residency numbers and
            # looks fully instrumented. This is the net under that.
            alert = "ModelGateMetricMissing";
            expr = ''
              halogen_rss_bytes unless on (host, instance) halogen_process_start_seconds
            '';
            for = "15m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "{{ $labels.host }} reports model residency without its cold-boot gate";
              description = "The collector publishes residency but not halogen_process_start_seconds, so HalogenWeightsNotFullyResident is disarmed on this host. Usually a collector that predates the gate or a failed read of /proc.";
            };
          }
          {
            # The alarm this whole group exists for: the engine mapped the whole
            # checkpoint but part of it is no longer resident, which means tokens
            # are being served off the NVMe. The mapped_bytes gate keeps a
            # half-loaded engine out of it; the start-time gate keeps a cold boot
            # out of it, because after a reboot resident starts near zero and
            # refills only as pages are touched, which is not eviction. An engine
            # restart alone never trips this: the page cache is per-inode and
            # survives it.
            alert = "HalogenWeightsNotFullyResident";
            expr = ''
              (min by (host, instance) (halogen_weights_mapped_bytes) > 1e10)
                and
              (min by (host, instance) (
                  halogen_weights_mapped_bytes - halogen_weights_resident_bytes
                ) > 1e9)
                and on (host, instance)
              (time() - halogen_process_start_seconds > 3600)
            '';
            for = "15m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "{{ $labels.host }} has dropped checkpoint pages to disk";
              description = "The engine has the whole checkpoint mapped, but part of it is no longer resident, so tokens are being read off the NVMe instead of RAM. Something evicted the model: look at what else claimed memory on {{ $labels.host }}.";
            };
          }
          {
            alert = "HalogenWeightsLockInactive";
            expr = "halogen_mlocked_bytes == 0";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "HALOGEN_WEIGHTS_LOCK is not in effect on {{ $labels.host }}";
              description = "Nothing is locked, so the checkpoint is reclaimable file cache and memory pressure can page the model out.";
            };
          }
          {
            # The engine's own measurement of the cost, so this is the alert that
            # says the drive - not the engine - is the limit. The exported value is
            # the worst read in a 15-minute window refreshed every 30s, so `for:
            # 10m` can fire on a single bad read from a quarter hour ago. That is
            # intended: one 12s stall is a stall a user felt, and it is worth saying
            # out loud once rather than averaging away.
            alert = "HalogenTableReadSlow";
            expr = "halogen_table_lookup_seconds > 10";
            for = "10m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "Lookup-table reads taking {{ $value }}s on {{ $labels.host }}";
              description = "The engine spent this long reading the lookup table for a request. Absence of this series is the normal state; a value in the tens of seconds means the table has nowhere to be cached.";
            };
          }
          {
            alert = "NvmeMediaErrors";
            expr = "nvme_media_errors_total > 0";
            for = "5m";
            labels = {
              severity = "critical";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} reports NVMe media and integrity errors";
              description = "The drive on {{ $labels.host }} has failed to write or read a block it should not have. Back it up and plan a replacement.";
            };
          }
          {
            alert = "NvmeEnduranceUsed";
            expr = "nvme_percentage_used >= 80 or nvme_available_spare_percent <= 20";
            for = "30m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} NVMe endurance or spare blocks are running low";
              description = "Either Percentage Used has reached 80 % of the drive's rated endurance or Available Spare has fallen to 20 %; check nvme_percentage_used and nvme_available_spare_percent on {{ $labels.host }} and order a replacement drive.";
            };
          }
          {
            alert = "NvmeSmartStatusFailed";
            expr = "nvme_smart_status_passed == 0";
            for = "5m";
            labels = {
              severity = "critical";
              tier = "host";
            };
            annotations = {
              summary = "{{ $labels.instance }} reports its NVMe health status as failing";
              description = "The drive on {{ $labels.host }} says so about itself. Back it up and replace it.";
            };
          }
          # Deliberately not alerted on: gpu_memory_used_bytes and
          # gpu_memory_pool_used_bytes{pool="gtt"}. On a unified-memory APU those
          # count the GPU's mapping window, not what is resident: fwai0 serves a
          # 62 GiB checkpoint with about 13 GiB of GTT in use, and a healthy
          # machine looks nearly empty there by design. Alerting on low GTT usage
          # reads a working host as a broken one (issue #888).
        ];
      }

      {
        name = "fleet-exit-node";
        rules = [
          {
            # The ISP-leak page: the kernel's route walk on the node no longer
            # reaches wg1, so tailnet traffic is egressing the local ISP. The
            # verdict is the route walk itself, not Mullvad's echo -- rented
            # Mullvad relays sit outside its announced prefixes, so an
            # IP-allow-list verdict pages on healthy nodes (issue #89 review).
            alert = "ExitNodeEgressNotMullvad";
            expr = "exit_node_egress_is_mullvad == 0";
            for = "2m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "Exit node {{ $labels.host }} egress is NOT via wg1";
              description = "`ip route get` on {{ $labels.host }} no longer resolves through wg1: tailnet traffic is leaking through the local ISP (wg1 down, or wg-quick's rule fell through to main).";
            };
          }
          {
            # Mullvad's echo endpoint unreachable while the route walk still
            # proves wg1: a Mullvad-side or internet outage, not a leak. Kept
            # separate from the leak page so that one stays honest (issue #89
            # review: probe failure and not-Mullvad must not collapse).
            alert = "ExitNodeProbeUnreachable";
            expr = "exit_node_egress_probe_ok == 0";
            for = "10m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "Exit node {{ $labels.host }} cannot reach Mullvad's egress echo";
              description = "am.i.mullvad.net did not answer from {{ $labels.host }}. The route-walk verdict is unaffected; this only removes the corroboration that the tunnel really lands on Mullvad.";
            };
          }
          {
            # One alert per family: a missing family breaks that family's
            # return path on its own (issue #55 review).
            alert = "ExitNodeRouteFixMissing";
            expr = "exit_node_route_fix_present == 0";
            for = "2m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "tailnet-route-fix rules missing or outranked on {{ $labels.host }} ({{ $labels.fam }})";
              description = "The proto-66 tailnet rule is absent or sits at/below wg-quick's lookup-51820 rule, so exit-node return traffic is swallowed by wg-quick's Mullvad default route. The unit died or wg-quick restarted without re-running it.";
            };
          }
          {
            # The incident failure: wg-quick's catch-all above Tailscale's
            # fwmark exemption strands tailscaled's control stream, DNS
            # forwarder and DERP conns inside the dead tunnel. Node stays
            # reachable, exit node is unusable -- invisible to the proto-66
            # check above (issue #89 review).
            alert = "ExitNodeFwmarkRouteStranded";
            expr = "exit_node_fwmark_route_ok == 0";
            for = "2m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "Marked (0x80000) traffic on {{ $labels.host }} routes via wg1, not the LAN";
              description = "Tailscale's fwmark exemption is outranked by wg-quick's rule: tailscaled's control stream and DERP conns are inside the tunnel they manage. Check `ip route get 1.1.1.1 mark 0x80000` and the rule order.";
            };
          }
          {
            # A stale handshake is the step before a leak: warn while wg1
            # still holds its last-known-good state.
            alert = "ExitNodeWgHandshakeStale";
            expr = "exit_node_wg_handshake_age_seconds > 300";
            for = "5m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "wg1 handshake on {{ $labels.host }} is over 5 minutes old";
              description = "The Mullvad tunnel has not re-handshaked recently; when the key expires the tunnel dies and egress falls back to the ISP.";
            };
          }
          {
            # The GpuMetricsMissing precedent: the scrape target carries
            # exit_node="true" from the inventory, so this is "a host that
            # must prove its egress and stopped reporting" -- a dead collector
            # must page as loudly as a leak, because absence of the proof is
            # the same operational state.
            alert = "ExitNodeMetricsMissing";
            expr = ''
              (up{job="fleet-node-exporters", exit_node="true"} == 1)
                unless on (host, instance) (exit_node_egress_is_mullvad)
            '';
            for = "10m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "No exit-node egress metrics from {{ $labels.instance }}";
              description = "{{ $labels.host }} is scraping but exports no exit_node_* metrics: the exit-node-metrics timer is dead, so the ISP-leak guarantee is unmonitored there.";
            };
          }
          {
            # Freshness, not presence: the textfile collector serves a stale
            # file forever, so a dead timer would freeze a green egress gauge.
            alert = "ExitNodeCollectionStale";
            expr = "time() - exit_node_metrics_timestamp_seconds > 180";
            for = "5m";
            labels = {
              severity = "warning";
              tier = "host";
            };
            annotations = {
              summary = "Exit-node metrics from {{ $labels.instance }} have not updated in 3 minutes";
              description = "exit-node-metrics.timer is not refreshing the textfile, so the egress verdict for {{ $labels.host }} is frozen rather than missing.";
            };
          }
        ];
      }

      {
        name = "fleet-services";
        rules = [
          {
            alert = "ServiceProbeFailed";
            expr = "probe_success == 0";
            for = "1m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "{{ $labels.service }} is not answering";
              description = "The {{ $labels.module }} probe against {{ $labels.instance }} has failed for a minute.";
            };
          }
          {
            alert = "ServiceHighLatency";
            expr = ''probe_http_duration_seconds{phase="total"} > 3'';
            for = "10m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "{{ $labels.service }} is taking over 3s to answer";
              description = "It is up, but it is slow enough to feel down from the inside.";
            };
          }
          {
            alert = "TLSCertificateExpiringSoon";
            expr = ''
              probe_ssl_earliest_cert_expiry - time() < 14 * 86400
            '';
            for = "30m";
            labels = {
              severity = "warning";
              tier = "service";
            };
            annotations = {
              summary = "TLS certificate for {{ $labels.instance }} expires in under 14 days";
              description = "ACME renewal has not landed; this is the last warning before clients start erroring.";
            };
          }
          {
            alert = "TLSCertificateExpiryCritical";
            expr = ''
              probe_ssl_earliest_cert_expiry - time() < 7 * 86400
                and probe_ssl_earliest_cert_expiry - time() > 0
            '';
            for = "10m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "TLS certificate for {{ $labels.instance }} expires in under 7 days";
            };
          }
          {
            alert = "TLSCertificateExpired";
            expr = "probe_ssl_earliest_cert_expiry - time() < 0";
            for = "5m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "TLS certificate for {{ $labels.instance }} has expired";
            };
          }
          {
            alert = "DnsProbeFailed";
            expr = "probe_dns_answer_rrs == 0";
            for = "5m";
            labels = {
              severity = "critical";
              tier = "service";
            };
            annotations = {
              summary = "DNS probe returned no answers ({{ $labels.instance }})";
            };
          }
        ];
      }

      {
        name = "fleet-storage";
        rules = [
          {
            # Every NFS-backed PVC in the cluster lives on this one export, so
            # it pages immediately and inhibits the per-volume noise below it.
            alert = "TankNfsServerDown";
            expr = ''probe_success{service="tank_nfs"} == 0'';
            for = "1m";
            labels = {
              severity = "critical";
              tier = "storage";
              cluster_critical = "true";
            };
            annotations = {
              summary = "homeserver tank NFS is unreachable -- cluster-critical";
              description = "Every dynamic PVC in k3s is a subdirectory of this export. NFS down means every volume's writes stall at once. Treat tank maintenance as a cluster-wide storage event: drain workloads first.";
            };
          }
          {
            alert = "TankCapacityLow";
            expr = ''
              node_filesystem_avail_bytes{mountpoint="/tank"}
                / node_filesystem_size_bytes{mountpoint="/tank"} < 0.15
            '';
            for = "30m";
            labels = {
              severity = "critical";
              tier = "storage";
              cluster_critical = "true";
            };
            annotations = {
              summary = "Tank is over 85% full";
              description = "In-cluster PVC bytes are tank bytes: an ENOSPC on the tank stalls every volume at once.";
            };
          }
          {
            alert = "TankPredictedFull";
            expr = ''
              predict_linear(node_filesystem_avail_bytes{mountpoint="/tank"}[24h], 4 * 24 * 3600) < 0
            '';
            for = "30m";
            labels = {
              severity = "critical";
              tier = "storage";
              cluster_critical = "true";
            };
            annotations = {
              summary = "Tank predicted full within 4 days at the current write rate";
            };
          }
          {
            alert = "NfsCsiControllerDown";
            expr = ''
              up{job="kube-system_csi-nfs-controller", namespace="kube-system"} == 0
            '';
            for = "5m";
            labels = {
              severity = "warning";
              tier = "storage";
            };
            annotations = {
              summary = "NFS CSI controller is not scraped -- no new PVCs can be provisioned";
            };
          }
          # SMART leading indicators. Each of these fires while the pool is still
          # ONLINE, which is the only moment they are worth anything: the pool's
          # own checksum errors are the lagging version of the same event, and by
          # then the disk has already cost you the redundancy.
          {
            # The only SMART signal that is unambiguous: the disk failed its own
            # health query. Everything below needs judgement.
            alert = "SmartDiskFailing";
            expr = "smart_status_passed == 0";
            for = "5m";
            labels = {
              severity = "critical";
              tier = "storage";
            };
            annotations = {
              summary = "{{ $labels.host }} disk {{ $labels.device }} reports SMART FAILURE";
              description = "smartctl reports the disk as failing. Deal with it before it stops answering: whichever mirror pair it belongs to is about to lose its redundancy, and a second failure in that pair is data loss.";
            };
          }
          {
            # Any nonzero count is the signal on modern drives. Firmware remaps
            # sparingly and only after a real read or write failure, so one
            # reallocated sector means the surface has already given up a block;
            # waiting for a threshold is waiting for a second opinion from a disk
            # that already gave its first.
            alert = "SmartReallocatedSectors";
            expr = "smart_reallocated_sectors > 0";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "storage";
            };
            annotations = {
              summary = "{{ $labels.host }} disk {{ $labels.device }} has reallocated sectors";
              description = "{{ $labels.device }} on {{ $labels.host }} has remapped {{ $value }} sectors. Back up before it grows, and check whether the pool has already logged errors against it.";
            };
          }
          {
            # Sectors the drive could not read and has queued for remap. These are
            # the ones ZFS already failed to read, so this leads a pool checksum
            # error rather than following it.
            alert = "SmartPendingSectors";
            expr = "smart_current_pending_sectors > 0";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "storage";
            };
            annotations = {
              summary = "{{ $labels.host }} disk {{ $labels.device }} has unreadable pending sectors";
              description = "{{ $labels.device }} on {{ $labels.host }} could not read {{ $value }} sectors and has queued them for remap. A resilver reads every block on the disk, so these are exactly what fails a rebuild -- and until the mirror's other half is verified, the copy you are relying on may be the damaged one.";
            };
          }
          {
            alert = "SmartUncorrectableSectors";
            expr = "smart_offline_uncorrectable > 0 or smart_reported_uncorrectable > 0 or smart_grown_defect_list > 0";
            for = "15m";
            labels = {
              severity = "warning";
              tier = "storage";
            };
            annotations = {
              summary = "{{ $labels.host }} disk {{ $labels.device }} has uncorrectable sectors";
              description = "{{ $labels.device }} on {{ $labels.host }} reports {{ $value }} sectors it could not correct at all. Data already written there may be unreadable; verify the pool's own error counters.";
            };
          }
          {
            # Not a fault, and it never pages: severity info routes to the null
            # receiver. It exists so HostDiskIOSaturated can be inhibited for the
            # duration of a scrub instead of silenced by hand or ignored.
            alert = "PoolScrubRunning";
            expr = "zpool_scrub_state == 1";
            labels = {
              severity = "info";
              tier = "storage";
            };
            annotations = {
              summary = "Scrub or resilver running on {{ $labels.host }} pool {{ $labels.pool }}";
              description = "{{ $labels.pool }} on {{ $labels.host }} is scrubbing. Disk saturation is expected for the duration, so HostDiskIOSaturated is inhibited on this host -- inhibited, not disabled, and it returns the moment the scrub ends.";
            };
          }
          {
            # Without this the inhibition fails open in the worst way: the
            # collector dies, PoolScrubRunning stops firing, and every scrub from
            # then on pages about saturated disks with no explanation.
            alert = "ZfsScrubMetricsMissing";
            expr = ''
              (up{job="fleet-node-exporters", zfs="true"} == 1)
                unless on (host, instance) (zpool_scrub_state)
            '';
            for = "15m";
            labels = {
              severity = "warning";
              tier = "storage";
            };
            annotations = {
              summary = "No ZFS scrub state from {{ $labels.instance }}";
              description = "{{ $labels.host }} is scraping but reports no pool scan state, so scrub-induced disk saturation is no longer inhibited and zpool_scrub_percent_done is dark; zfs-scrub-state.timer is not refreshing the textfile or no pool answered.";
            };
          }
        ];
      }

      {
        name = "monitoring-itself";
        rules = [
          {
            # Dead-man switch: fires constantly by design. Any gap in the
            # pipeline (Prometheus, Alertmanager, the mail path) shows up as the
            # absence of the heartbeat, not as an alert.
            alert = "Watchdog";
            expr = "vector(1)";
            labels = {
              severity = "none";
              tier = "meta";
            };
            annotations = {
              summary = "Heartbeat: the alerting pipeline is evaluating";
              description = "This alert is always firing. If the receiving side stops seeing it, the pipeline -- not the fleet -- is the problem.";
            };
          }
          {
            alert = "PrometheusConfigReloadFailed";
            expr = "prometheus_config_last_reload_successful == 0";
            for = "5m";
            labels = {
              severity = "critical";
              tier = "meta";
            };
            annotations = {
              summary = "Prometheus is running a stale config";
              description = "The last config reload failed, so recent inventory changes are not being scraped.";
            };
          }
          {
            alert = "PrometheusTargetLoss";
            expr = ''
              count(up == 1) < 0.6 * count(up)
            '';
            for = "10m";
            labels = {
              severity = "critical";
              tier = "meta";
            };
            annotations = {
              summary = "Most Prometheus targets are down";
              description = "More than 40% of scrape targets are failing: this is a monitoring outage, not a fleet outage.";
            };
          }
          # Mail-delivery failure is already covered by the chart's own
          # AlertmanagerFailedToSendAlerts rule, so there is nothing to add here.
        ];
      }
    ];
  };

  # Alertmanager routing: group by what broke, inhibit the service noise under a
  # host outage, and send everything to mail (see `mailReceiver`).
  alertmanagerConfig = mail: {
    global = {
      resolve_timeout = "5m";
      smtp_smarthost = mail.smtpHost;
      smtp_hello = mail.heloDomain;
      smtp_from = mail.from;
      # Submission is to Stalwart's internal listener (2525) over the tailnet;
      # unauthenticated fleet mail is exempt from SPF/spam checks there, and
      # STARTTLS is not required on the tailnet.
      smtp_require_tls = false;
    };

    route = {
      receiver = "mail";
      group_by = [
        "alertname"
        "host"
      ];
      group_wait = "1m";
      group_interval = "10m";
      repeat_interval = "4h";
      routes = [
        {
          # Watchdog is a heartbeat, not a page: never delivered.
          matchers = [ ''alertname = "Watchdog"'' ];
          receiver = "null";
        }
        {
          matchers = [ ''severity = "info"'' ];
          receiver = "null";
        }
      ];
    };

    inhibit_rules = [
      {
        # A scrub reads every block on every disk on purpose, so io_time above
        # 90% is literally true and completely unactionable for as long as it
        # runs -- hours on a full pool. Inhibited rather than dropped, so the
        # saturation alert still exists and returns the moment the scrub ends.
        source_matchers = [ ''alertname = "PoolScrubRunning"'' ];
        target_matchers = [ ''alertname = "HostDiskIOSaturated"'' ];
        equal = [ "host" ];
      }
      {
        # A dead host explains every failing probe on it.
        source_matchers = [ ''alertname = "HostDown"'' ];
        target_matchers = [ ''tier =~ "service|storage"'' ];
        equal = [ "host" ];
      }
      {
        source_matchers = [ ''cluster_critical = "true"'' ];
        target_matchers = [ ''severity =~ "warning|info"'' ];
      }
      {
        source_matchers = [ ''severity = "critical"'' ];
        target_matchers = [ ''severity = "warning"'' ];
        equal = [
          "host"
          "instance"
        ];
      }
    ];

    receivers = [
      {
        name = "mail";
        email_configs = [
          {
            to = mail.to;
            send_resolved = true;
            headers = {
              Subject = ''[{{ .Status | toUpper }}{{ if eq .Status "firing" }}/{{ .CommonLabels.alertname }}{{ end }}] {{ .CommonAnnotations.summary }}'';
            };
          }
        ];
      }
      { name = "null"; }
    ];

    templates = [ "/etc/alertmanager/config/*.tmpl" ];
  };
in
{
  inherit scrapeConfigs rules alertmanagerConfig;
}
