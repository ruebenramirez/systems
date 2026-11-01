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
      # Submission is to Stalwart's public MX listener over the tailnet; it is
      # an unauthenticated relay by design, and STARTTLS is not offered there.
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
