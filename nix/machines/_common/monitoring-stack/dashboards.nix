# Grafana dashboards, generated from the fleet inventory and shipped to the
# cluster as sidecar-discovered ConfigMaps (label `grafana_dashboard: "1"`).
#
# Two dashboards carry the drill-down the status page links into:
#   fleet-host-health    ?var-host=<host>     one host's CPU/RAM/disk/IO/systemd
#   fleet-service-probes ?var-service=<name>  one service's probes and cert age
# Everything else is fleet-wide. Kubernetes-level dashboards (apiserver, etcd,
# scheduler, pods/nodes) ship with kube-prometheus-stack and are not duplicated
# here.
{ inventory }:
let
  ds = {
    type = "prometheus";
    uid = "prometheus";
  };

  # Panel constructors keep the dashboards below readable.
  ts =
    {
      id,
      title,
      expr,
      legend ? "{{instance}}",
      unit ? "short",
      x,
      y,
      w ? 12,
      h ? 8,
      min ? null,
      max ? null,
      stack ? false,
      instant ? false,
    }:
    {
      inherit id title;
      type = "timeseries";
      datasource = ds;
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      fieldConfig = {
        defaults = {
          inherit unit min max;
          custom = {
            inherit stack;
            fillOpacity = 10;
            lineWidth = 1;
            showPoints = "never";
          };
        };
        overrides = [ ];
      };
      targets = [
        {
          inherit expr instant;
          legendFormat = legend;
          refId = "A";
        }
      ];
    };

  stat =
    {
      id,
      title,
      expr,
      unit ? "short",
      x,
      y,
      w ? 4,
      h ? 4,
      threshold ? null,
      reduce ? "last",
      min ? null,
      max ? null,
    }:
    {
      inherit id title;
      type = "stat";
      datasource = ds;
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      fieldConfig = {
        defaults = {
          inherit unit min max;
          mappings = [ ];
          thresholds =
            if threshold == null then
              {
                mode = "absolute";
                steps = [ { color = "green"; } ];
              }
            else
              {
                mode = "absolute";
                steps = threshold;
              };
        };
        overrides = [ ];
      };
      options = {
        colorMode = "background";
        graphMode = "none";
        reduceOptions = {
          calcs = [ reduce ];
          fields = "";
          values = false;
        };
        textMode = "auto";
      };
      targets = [
        {
          expr = builtins.replaceStrings [ "$__range_var" ] [ "5m" ] expr;
          instant = true;
          intervalFactor = 1;
          refId = "A";
        }
      ];
    };

  table =
    {
      id,
      title,
      expr,
      x,
      y,
      w ? 24,
      h ? 8,
      instant ? true,
      legend ? "",
    }:
    {
      inherit id title;
      type = "table";
      datasource = ds;
      gridPos = {
        inherit
          x
          y
          w
          h
          ;
      };
      options = {
        showHeader = true;
        footer = {
          reducer = [ "count" ];
          countRows = false;
          show = false;
        };
        sortBy = [ ];
      };
      fieldConfig = {
        defaults = {
          custom = { };
        };
        overrides = [ ];
      };
      targets = [
        {
          inherit expr instant;
          format = "table";
          refId = "A";
        }
      ];
    };

  row = id: title: y: {
    inherit id title y;
    type = "row";
    collapsed = false;
    gridPos = {
      h = 1;
      w = 24;
      x = 0;
      inherit y;
    };
    panels = [ ];
  };

  queryVar = name: query: label: {
    inherit name label;
    type = "query";
    datasource = ds;
    query = {
      query = builtins.replaceStrings [ "$NAME" ] [ name ] query;
      refId = "${name}-var";
    };
    refresh = 2;
    regex = "";
    sort = 1;
    multi = false;
    includeAll = false;
    options = [ ];
    current = { };
  };

  dashboard =
    {
      uid,
      title,
      tags ? [ ],
      panels,
      varList ? [ ],
      description ? "",
    }:
    {
      inherit uid title;
      annotations = {
        list = [
          {
            builtIn = 1;
            datasource = {
              type = "grafana";
              uid = "-- Grafana --";
            };
            enable = true;
            hide = true;
            iconColor = "rgba(0, 211, 255, 1)";
            name = "Annotations & Alerts";
            type = "dashboard";
          }
        ];
      };
      editable = true;
      fiscalYearStartMonth = 0;
      graphTooltip = 1;
      id = null;
      inherit description;
      links = [ ];
      liveNow = false;
      inherit panels;
      refresh = "1m";
      schemaVersion = 39;
      tags = tags ++ [ "fleet" ];
      templating = {
        list = varList;
      };
      time = {
        from = "6h";
        to = "now";
      };
      timepicker = { };
      timezone = "";
      version = 1;
      weekStart = "";
    };

  fsFilter = ''fstype!~"tmpfs|ramfs|vfat|overlay|autofs"'';

  hostHealth = dashboard {
    uid = "fleet-host-health";
    title = "Fleet Host Health";
    description = "Per-host drill-down: what one machine is doing right now.";
    varList = [
      (queryVar "host" "label_values(node_uname_info, host)" "Host")
    ];
    panels = [
      (row 1 "Vitals" 0)
      (stat {
        id = 2;
        title = "Scraping";
        x = 0;
        y = 1;
        expr = ''up{job="fleet-node-exporters", host="$host"}'';
        threshold = [
          { color = "red"; }
          { color = "green"; }
        ];
      })
      (stat {
        id = 3;
        title = "Uptime";
        x = 4;
        y = 1;
        unit = "s";
        expr = ''time() - node_boot_time_seconds{host="$host"}'';
      })
      (stat {
        id = 4;
        title = "CPU busy";
        x = 8;
        y = 1;
        unit = "percent";
        threshold = [
          { color = "green"; }
          {
            color = "orange";
            value = 80;
          }
          {
            color = "red";
            value = 95;
          }
        ];
        expr = ''(1 - avg(rate(node_cpu_seconds_total{host="$host",mode="idle"}[5m]))) * 100'';
      })
      (stat {
        id = 5;
        title = "Memory used";
        x = 12;
        y = 1;
        unit = "percent";
        threshold = [
          { color = "green"; }
          {
            color = "orange";
            value = 80;
          }
          {
            color = "red";
            value = 92;
          }
        ];
        expr = ''(1 - node_memory_MemAvailable_bytes{host="$host"} / node_memory_MemTotal_bytes{host="$host"}) * 100'';
      })
      (stat {
        id = 6;
        title = "Load 15";
        x = 16;
        y = 1;
        expr = ''node_load15{host="$host"}'';
      })
      (stat {
        id = 7;
        title = "Failed units";
        x = 20;
        y = 1;
        threshold = [
          { color = "green"; }
          {
            color = "red";
            value = 1;
          }
        ];
        expr = ''count(node_systemd_unit_state{host="$host",state="failed"} == 1) or vector(0)'';
      })
      (row 8 "CPU / memory" 5)
      (ts {
        id = 9;
        title = "CPU by mode";
        unit = "percentunit";
        min = 0;
        max = 1;
        stack = true;
        x = 0;
        y = 6;
        w = 12;
        legend = "{{mode}}";
        expr = ''avg by (mode) (rate(node_cpu_seconds_total{host="$host"}[5m]))'';
      })
      (ts {
        id = 10;
        title = "Memory";
        unit = "bytes";
        x = 12;
        y = 6;
        w = 12;
        legend = "{{state}}";
        expr = ''node_memory_MemTotal_bytes{host="$host"} - node_memory_MemAvailable_bytes{host="$host"}'';
      })
      (ts {
        id = 11;
        title = "CPU load average";
        x = 0;
        y = 14;
        w = 12;
        legend = "{{item}}";
        expr = ''node_load{host="$host"}'';
      })
      (ts {
        id = 12;
        title = "Context switches / interrupts";
        x = 12;
        y = 14;
        w = 12;
        legend = "{{item}}";
        expr = ''rate(node_context_switches_total{host="$host"}[5m]) or rate(node_intr_total{host="$host"}[5m])'';
      })
      (row 13 "Disk" 22)
      (ts {
        id = 14;
        title = "Filesystem used";
        unit = "percentunit";
        min = 0;
        max = 1;
        x = 0;
        y = 23;
        legend = "{{mountpoint}} ({{device}})";
        expr = ''1 - node_filesystem_avail_bytes{host="$host",${fsFilter}} / node_filesystem_size_bytes{host="$host",${fsFilter}}'';
      })
      (ts {
        id = 15;
        title = "Space predicted to remain (4h horizon; negative = full)";
        unit = "bytes";
        x = 12;
        y = 23;
        legend = "{{mountpoint}}";
        expr = ''predict_linear(node_filesystem_avail_bytes{host="$host",${fsFilter}}[6h], 4 * 3600)'';
      })
      (ts {
        id = 16;
        title = "Disk I/O utilisation";
        unit = "percentunit";
        min = 0;
        x = 0;
        y = 31;
        legend = "{{device}}";
        expr = ''rate(node_disk_io_time_seconds_total{host="$host"}[5m])'';
      })
      (ts {
        id = 17;
        title = "Disk throughput";
        unit = "Bps";
        x = 12;
        y = 31;
        legend = "{{device}} {{operation}}";
        expr = ''rate(node_disk_read_bytes_total{host="$host"}[5m]) or rate(node_disk_written_bytes_total{host="$host"}[5m])'';
      })
      (row 18 "Network" 39)
      (ts {
        id = 19;
        title = "Bandwidth";
        unit = "Bps";
        x = 0;
        y = 40;
        legend = "{{device}} {{direction}}";
        expr = ''rate(node_network_receive_bytes_total{host="$host"}[5m]) or rate(node_network_transmit_bytes_total{host="$host"}[5m])'';
      })
      (ts {
        id = 20;
        title = "Interface errors / drops";
        x = 12;
        y = 40;
        legend = "{{device}} {{direction}}";
        expr = ''rate(node_network_receive_errs_total{host="$host"}[5m]) or rate(node_network_transmit_errs_total{host="$host"}[5m]) or rate(node_network_receive_drop_total{host="$host"}[5m])'';
      })
      # Shown for every host: on a box with no GPU the collector writes nothing,
      # so these panels stay empty rather than inventing a series.
      (row 23 "GPU" 48)
      (ts {
        id = 24;
        title = "GPU utilisation";
        unit = "percent";
        min = 0;
        max = 100;
        x = 0;
        y = 49;
        w = 12;
        legend = "{{gpu}}";
        expr = ''gpu_utilization_percent{host="$host"}'';
      })
      (ts {
        id = 25;
        title = "VRAM used";
        unit = "percentunit";
        min = 0;
        max = 1;
        x = 12;
        y = 49;
        w = 12;
        legend = "{{gpu}}";
        # Fraction rather than bytes: the useful question is how close the card is
        # to full, and the two hosts do not have the same card.
        expr = ''gpu_memory_used_bytes{host="$host"} / gpu_memory_total_bytes{host="$host"}'';
      })
      (ts {
        id = 26;
        title = "GPU power";
        unit = "watt";
        min = 0;
        x = 0;
        y = 57;
        w = 12;
        legend = "{{gpu}}";
        expr = ''gpu_power_watts{host="$host"}'';
      })
      (ts {
        id = 27;
        title = "GPU temperature";
        unit = "celsius";
        min = 0;
        x = 12;
        y = 57;
        w = 12;
        legend = "{{gpu}}";
        expr = ''gpu_temperature_celsius{host="$host"}'';
      })
      (row 21 "systemd" 65)
      (table {
        id = 22;
        title = "Failed units";
        x = 0;
        y = 66;
        expr = ''node_systemd_unit_state{host="$host",state="failed"} == 1'';
      })
    ];
  };

  serviceProbes = dashboard {
    uid = "fleet-service-probes";
    title = "Fleet Service Probes";
    description = "Blackbox view of every inventoried service, with TLS expiry.";
    varList = [
      (queryVar "service" "label_values(probe_success, service)" "Service")
      (queryVar "host" "label_values(probe_success{service=\"$service\"}, host)" "Host")
    ];
    panels = [
      (stat {
        id = 1;
        title = "Probe result";
        x = 0;
        y = 0;
        threshold = [
          { color = "red"; }
          {
            color = "green";
            value = 1;
          }
        ];
        expr = ''probe_success{service="$service"}'';
      })
      (stat {
        id = 2;
        title = "Response time";
        x = 4;
        y = 0;
        unit = "s";
        expr = ''probe_duration_seconds{service="$service"}'';
      })
      (stat {
        id = 3;
        title = "TLS cert days left";
        x = 8;
        y = 0;
        unit = "d";
        threshold = [
          { color = "red"; }
          {
            color = "orange";
            value = 14;
          }
          {
            color = "green";
            value = 30;
          }
        ];
        expr = ''(probe_ssl_earliest_cert_expiry{service="$service"} - time()) / 86400'';
      })
      (stat {
        id = 4;
        title = "HTTP status";
        x = 12;
        y = 0;
        expr = ''probe_http_status_code{service="$service"}'';
      })
      (ts {
        id = 5;
        title = "Probe success over time (0 = down)";
        x = 0;
        y = 4;
        w = 12;
        min = 0;
        max = 1;
        legend = "{{instance}}";
        expr = ''probe_success{service="$service"}'';
      })
      (ts {
        id = 6;
        title = "Probe duration";
        unit = "s";
        x = 12;
        y = 4;
        w = 12;
        legend = "{{instance}}";
        expr = ''probe_duration_seconds{service="$service"}'';
      })
      (table {
        id = 7;
        title = "Every service, right now";
        x = 0;
        y = 12;
        expr = "probe_success";
      })
      (table {
        id = 8;
        title = "TLS expiry (days)";
        x = 0;
        y = 20;
        expr = "(probe_ssl_earliest_cert_expiry - time()) / 86400";
      })
    ];
  };

  overview = dashboard {
    uid = "fleet-overview";
    title = "Fleet Overview";
    description = "One screen for the whole fleet: what is up, what is filling, what is firing.";
    panels = [
      (stat {
        id = 1;
        title = "Hosts scraping";
        x = 0;
        y = 0;
        expr = ''count(up{job="fleet-node-exporters"} == 1)'';
      })
      (stat {
        id = 2;
        title = "Probes failing";
        x = 4;
        y = 0;
        threshold = [
          { color = "green"; }
          {
            color = "red";
            value = 1;
          }
        ];
        expr = "count(probe_success == 0) or vector(0)";
      })
      (stat {
        id = 3;
        title = "Alerts firing";
        x = 8;
        y = 0;
        threshold = [
          { color = "green"; }
          {
            color = "orange";
            value = 1;
          }
        ];
        expr = ''count(ALERTS{alertstate="firing", alertname!="Watchdog"}) or vector(0)'';
      })
      (stat {
        id = 4;
        title = "Scrape targets up";
        x = 12;
        y = 0;
        unit = "percentunit";
        min = 0;
        max = 1;
        expr = "count(up == 1) / count(up)";
      })
      (ts {
        id = 5;
        title = "CPU busy by host";
        unit = "percent";
        min = 0;
        max = 100;
        x = 0;
        y = 4;
        w = 12;
        legend = "{{host}}";
        expr = ''(1 - avg by (host) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100'';
      })
      (ts {
        id = 6;
        title = "Memory used by host";
        unit = "percent";
        min = 0;
        max = 100;
        x = 12;
        y = 4;
        w = 12;
        legend = "{{host}}";
        expr = "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100";
      })
      (ts {
        id = 7;
        title = "Filesystem free (percent)";
        unit = "percent";
        min = 0;
        max = 100;
        x = 0;
        y = 12;
        w = 12;
        legend = "{{host}} {{mountpoint}}";
        expr = "100 * node_filesystem_avail_bytes{${fsFilter}} / node_filesystem_size_bytes{${fsFilter}} < 30";
      })
      (ts {
        id = 8;
        title = "Services failing";
        x = 12;
        y = 12;
        w = 12;
        legend = "{{service}}";
        expr = "probe_success == 0";
      })
      (table {
        id = 9;
        title = "Hosts not scraping";
        x = 0;
        y = 20;
        expr = ''up{job="fleet-node-exporters"} == 0'';
      })
      # Fleet-wide GPU glance: which box is actually computing, and which is
      # quietly holding all its VRAM. Per-card detail is the host dashboard.
      (row 10 "GPU" 28)
      (ts {
        id = 11;
        title = "GPU utilisation";
        unit = "percent";
        min = 0;
        max = 100;
        x = 0;
        y = 29;
        w = 12;
        legend = "{{host}} {{gpu}}";
        expr = "gpu_utilization_percent";
      })
      (ts {
        id = 12;
        title = "GPU VRAM used";
        unit = "bytes";
        min = 0;
        x = 12;
        y = 29;
        w = 12;
        legend = "{{host}} {{gpu}}";
        expr = "gpu_memory_used_bytes";
      })
    ];
  };

  # One ConfigMap per dashboard, in the shape the grafana sidecar discovers.
  toConfigMap = dash: {
    apiVersion = "v1";
    kind = "ConfigMap";
    metadata = {
      name = "grafana-dash-${dash.uid}";
      namespace = "monitoring";
      labels = {
        grafana_dashboard = "1";
        "app.kubernetes.io/part-of" = "fleet-monitoring";
      };
    };
    data = {
      "${dash.uid}.json" = builtins.toJSON dash;
    };
  };
in
map toConfigMap [
  hostHealth
  serviceProbes
  overview
]
