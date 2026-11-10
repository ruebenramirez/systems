# The fleet's service inventory: one entry per thing that must stay up.
#
# This file is the only place monitoring information is written down. Everything
# the monitoring stack consumes is generated from it -- Prometheus static scrape
# targets, blackbox probe targets and modules, Gatus status-page endpoints, and
# the Grafana dashboard variables -- so standing up a new service is one edit
# here rather than four edits in three languages.
#
# Plain Nix (no `lib`, no module system): it is imported both by NixOS modules
# and by generation scripts, and it must stay evaluable without nixpkgs.
#
# Conventions:
#   - `host` must be a key of `hosts` below, which is keyed by `networking.hostName`.
#   - `probe.module` is a blackbox exporter module name (see `blackboxModules`).
#   - `status = false` keeps the probe and its alert but hides the tile from the
#     status page -- for plumbing that is not worth a green square.
#   - Addresses are tailnet names (nix/lib/tailnet.nix) when the thing is only
#     reachable from the tailnet, and public FQDNs when the world must resolve
#     them too.
rec {
  tailnet = import ./tailnet.nix;

  # ---------------------------------------------------------------- hosts ---

  # `monitored = false` keeps a host out of every generated list; `driver` is
  # excluded by decision (a laptop, not a server). `offlineOk = true` lets a
  # whole-fleet deploy skip an unreachable host instead of failing the run.
  # `gpu = true` says the host has
  # a GPU whose metrics must show up: it labels the scrape target, turns on the
  # collector in nix/machines/_common/monitoring.nix, and is what the
  # GpuMetricsMissing alert holds the host to. `llm = true` does the same for the
  # host running the model server, whose memory no other metric can see.
  hosts = {
    homeserver = {
      description = "Mail (Stalwart), media, headscale, Forgejo origin, tank NFS";
      zfs = true;
      gpu = true;
    };
    fwai0 = {
      description = "Fleet build farm, LLM inference";
      gpu = true;
      llm = true;
    };
    ssdnodes-1 = {
      description = "Public VPS: public MX, Matrix, DERP, hosted sites";
      zfs = true;
    };
    xps17 = {
      description = "Incus hypervisor for the fleet VMs";
      zfs = true;
    };
    pi-syncoid-target = {
      description = "Off-box ZFS backup target (Raspberry Pi)";
      zfs = true;
    };
    dev-vm-xps = {
      description = "Development VM (Podman, editor, data share)";
    };
    download-vm-xps = {
      description = "Torrent/NAS download VM, Mullvad exit";
      # Must export exit-node egress metrics (see _common/exit-node-monitor.nix);
      # labels the scrape target the way `gpu`/`llm` do, so the missing-metric
      # alert can hold this host to producing them.
      exitNode = true;
    };
    hermes-vm-xps = {
      description = "Hermes agent VM";
    };
    forgejo-ci-runner-vm = {
      description = "Forgejo CI runner (also the fleet deploy runner)";
    };
    k3s-1 = {
      description = "k3s server 1 (HA control plane, monitoring workloads)";
    };
    k3s-2 = {
      description = "k3s server 2 (HA control plane)";
    };
    k3s-3 = {
      description = "k3s server 3 (HA control plane)";
    };
    driver = {
      description = "Personal laptop -- deliberately unmonitored";
      monitored = false;
      # not expected to be awake at 03:30; dark is normal, not an incident
      offlineOk = true;
    };
  };

  # node_exporter listens on this port on every monitored host; the scrape
  # targets and the firewall allowlist both come from this plus `hosts`.
  nodeExporterPort = 9100;

  # Derived: the hosts that get an exporter and a scrape target.
  monitoredHosts = builtins.filter (n: (hosts.${n}.monitored or true)) (builtins.attrNames hosts);

  # Derived: hosts a whole-fleet deploy may skip when ssh fails instead of
  # failing the run (laptops that are legitimately asleep at 03:30).
  offlineOkHosts = builtins.filter (n: (hosts.${n}.offlineOk or false)) (builtins.attrNames hosts);

  # ------------------------------------------------------------ zfs pools ---

  # Pools whose capacity the fleet watches. `mountpoint` must name a dataset
  # mountpoint, never the pool's own root: tankbak's root mount reports 1% used
  # while tankbak/data -- the same pool, 81% full -- reports 82%.
  zfsPools = [
    {
      host = "homeserver";
      pool = "tank";
      mountpoint = "/tank";
    }
    {
      host = "pi-syncoid-target";
      pool = "tankbak";
      mountpoint = "/tankbak/data";
    }
  ];

  # ------------------------------------------------------------- services ---

  services = {
    # ---- homeserver -------------------------------------------------------
    stalwart-smtp = {
      host = "homeserver";
      title = "Stalwart SMTP";
      group = "mail";
      probe = {
        # Connect-only on purpose. A full EHLO from the cluster fails Stalwart's
        # forward-confirmed-reverse-DNS check on the EHLO name, and repeated
        # failures get the source tarpitted -- so a chatty probe here invents
        # outages. End-to-end mail delivery is covered by AlertmailDeliveryFailing.
        module = "tcp";
        target = "mail.rueb.dev:25";
      };
      status = false;
    };
    stalwart-submission = {
      host = "homeserver";
      title = "Stalwart Submission";
      group = "mail";
      probe = {
        module = "tcp";
        target = "mail.rueb.dev:587";
      };
      status = false;
    };
    stalwart-imap = {
      host = "homeserver";
      title = "Stalwart IMAP";
      group = "mail";
      probe = {
        module = "imap";
        target = "mail.rueb.dev:993";
      };
      status = false;
    };
    stalwart-admin = {
      host = "homeserver";
      title = "Stalwart Web Admin";
      group = "mail";
      probe = {
        module = "http";
        target = "https://mail.rueb.dev/";
      };
    };
    webmail = {
      host = "homeserver";
      title = "Webmail";
      group = "mail";
      probe = {
        module = "http";
        target = "https://webmail.rueb.dev/";
      };
    };
    forgejo = {
      host = "homeserver";
      title = "Forgejo";
      group = "code";
      probe = {
        module = "http";
        target = "https://code.rueb.dev/";
      };
    };
    jellyfin = {
      host = "homeserver";
      title = "Jellyfin";
      group = "media";
      probe = {
        module = "http";
        target = "https://tv.rueb.dev/";
      };
    };
    immich = {
      host = "homeserver";
      title = "Immich";
      group = "media";
      probe = {
        module = "tcp";
        target = "${tailnet.host "homeserver"}:3001";
      };
    };
    audiobookshelf = {
      host = "homeserver";
      title = "Audiobookshelf";
      group = "media";
      probe = {
        module = "http";
        target = "https://audiobooks.rueb.dev/";
      };
    };
    freshrss = {
      host = "homeserver";
      title = "FreshRSS";
      group = "feeds";
      probe = {
        module = "http";
        target = "https://freshrss.rueb.dev/";
      };
    };
    searxng = {
      host = "homeserver";
      title = "SearXNG";
      group = "search";
      probe = {
        module = "http";
        target = "https://search.rueb.dev/";
      };
    };
    headscale = {
      host = "homeserver";
      title = "Headscale";
      group = "network";
      probe = {
        module = "http";
        target = "https://hs.rueb.dev/";
      };
    };
    tank-nfs = {
      host = "homeserver";
      title = "Tank NFS (VM and PVC shares)";
      group = "storage";
      probe = {
        module = "tcp";
        target = "192.168.8.150:2049";
      };
    };
    # PostgreSQL and Redis bind loopback only, so no external probe can see
    # them; their systemd unit state (node_exporter) is what alerts on.

    # ---- ssdnodes-1 -------------------------------------------------------
    matrix = {
      host = "ssdnodes-1";
      title = "Matrix homeserver";
      group = "matrix";
      probe = {
        module = "http";
        target = "https://matrix.rueb.dev/_matrix/client/versions";
      };
    };
    site-monicaandrueben = {
      host = "ssdnodes-1";
      title = "monicaandrueben.com";
      group = "web";
      probe = {
        module = "http";
        target = "https://monicaandrueben.com/";
      };
    };
    site-monicarosephotography = {
      host = "ssdnodes-1";
      title = "monicarosephotography.com";
      group = "web";
      probe = {
        module = "http";
        target = "https://monicarosephotography.com/";
      };
    };
    public-mx = {
      host = "ssdnodes-1";
      title = "Public MX relay";
      group = "mail";
      probe = {
        # Probed over the tailnet, not 172.93.51.14:25: the home ISP filters
        # outbound 25, so from this vantage the public listener is unreachable
        # whether or not it is healthy. This proves the relay is listening; it
        # cannot prove the internet can reach it.
        module = "tcp";
        target = "${tailnet.host "ssdnodes-1"}:25";
      };
      status = false;
    };
    derp = {
      host = "ssdnodes-1";
      title = "DERP relay";
      group = "network";
      probe = {
        module = "tcp";
        target = "172.93.51.14:443";
      };
    };

    # ---- infra hosts (ssh is the service that matters) --------------------
    xps17-ssh = {
      host = "xps17";
      title = "xps17 SSH (Incus host)";
      group = "infra";
      probe = {
        module = "tcp";
        target = "${tailnet.host "xps17"}:22";
      };
      status = false;
    };
    fwai0-ssh = {
      host = "fwai0";
      title = "fwai0 SSH (builder)";
      group = "infra";
      probe = {
        module = "tcp";
        target = "${tailnet.host "fwai0"}:22";
      };
      status = false;
    };
    pi-ssh = {
      host = "pi-syncoid-target";
      title = "pi-syncoid-target SSH";
      group = "infra";
      probe = {
        module = "tcp";
        target = "${tailnet.host "pi-syncoid-target"}:22";
      };
      status = false;
    };

    # ---- fleet VMs --------------------------------------------------------
    hermes-agent = {
      host = "hermes-vm-xps";
      title = "Hermes agent";
      group = "agents";
      probe = {
        module = "tcp";
        target = "${tailnet.host "hermes-vm-xps"}:8644";
      };
    };

    # ---- k3s cluster ------------------------------------------------------
    k3s-api-1 = {
      host = "k3s-1";
      title = "k3s API (k3s-1)";
      group = "k3s";
      probe = {
        module = "tcp";
        target = "${tailnet.host "k3s-1"}:6443";
      };
      status = false;
    };
    k3s-api-2 = {
      host = "k3s-2";
      title = "k3s API (k3s-2)";
      group = "k3s";
      probe = {
        module = "tcp";
        target = "${tailnet.host "k3s-2"}:6443";
      };
      status = false;
    };
    k3s-api-3 = {
      host = "k3s-3";
      title = "k3s API (k3s-3)";
      group = "k3s";
      probe = {
        module = "tcp";
        target = "${tailnet.host "k3s-3"}:6443";
      };
      status = false;
    };
    prometheus = {
      host = "k3s-1";
      title = "Prometheus";
      group = "monitoring";
      probe = {
        module = "http";
        target = "http://prometheus-operated.monitoring.svc.cluster.local:9090/-/ready";
      };
      status = false;
    };
    alertmanager = {
      host = "k3s-1";
      title = "Alertmanager";
      group = "monitoring";
      probe = {
        module = "http";
        target = "https://alerts.rueb.dev/-/healthy";
      };
    };
    grafana = {
      host = "k3s-1";
      title = "Grafana";
      group = "monitoring";
      probe = {
        module = "http";
        target = "https://monitoring.rueb.dev/api/health";
      };
    };
    gatus = {
      host = "k3s-1";
      title = "Gatus status page";
      group = "monitoring";
      probe = {
        module = "http";
        target = "https://status.rueb.dev/";
      };
    };
    harbor = {
      host = "k3s-1";
      title = "Harbor registry";
      group = "registry";
      # Harbor's own aggregate health endpoint: it reports on core, database,
      # registry, redis and the portal in one answer, which is a better probe
      # than the portal root (a 200 there only proves nginx is up).
      probe = {
        module = "http";
        target = "https://harbor.rueb.dev/api/v2.0/health";
      };
    };
  };

  # --------------------------------------------------------- blackbox bits ---

  # blackbox_exporter modules referenced by `services.*.probe.module`, rendered
  # verbatim into its config. ICMP is deliberately absent: it needs CAP_NET_RAW
  # in-cluster, and a TCP connect to sshd says the same thing about a host.
  # Probes target names rather than addresses wherever possible so the probes
  # follow the same DNS the services do; blackbox resolves them at probe time.
  #
  # Every module pins IPv4: the cluster egresses over a tailnet with no IPv6
  # route, and blackbox treats "network is unreachable" on an AAAA as a failed
  # probe instead of falling back -- which would make every Cloudflare-fronted
  # site look down while it is fine.
  blackboxModules = {
    http = {
      prober = "http";
      timeout = "10s";
      # Prober options live under the prober's own key, not at module level.
      http = {
        follow_redirects = true;
        valid_status_codes = [ ];
        preferred_ip_protocol = "ip4";
      };
    };
    tcp = {
      prober = "tcp";
      timeout = "5s";
      tcp = {
        preferred_ip_protocol = "ip4";
      };
    };
    imap = {
      prober = "tcp";
      timeout = "10s";
      tcp = {
        tls = true;
        preferred_ip_protocol = "ip4";
        query_response = [
          { expect = "^\\* OK"; }
          { send = "a1 LOGOUT"; }
          { expect = "^\\* BYE"; }
        ];
      };
    };
  };

  # Inventory entries as a list, carrying their attribute name as `key`.
  serviceList =
    let
      entries = builtins.attrValues (builtins.mapAttrs (name: s: s // { inherit name; }) services);
    in
    builtins.filter (s: builtins.elem s.host monitoredHosts) entries;

  # Probe targets grouped by blackbox module, for prometheus static_configs.
  # One target group per probe so `service` labels stay one-to-one.
  probeTargetsByModule =
    let
      grouped = builtins.foldl' (
        acc: s:
        acc
        // {
          ${s.probe.module} = (acc.${s.probe.module} or [ ]) ++ [
            {
              targets = [ s.probe.target ];
              labels = {
                service = s.name;
                host = s.host;
              };
            }
          ];
        }
      ) { } serviceList;
    in
    grouped;

  # Status-page endpoints (Gatus): everything not marked `status = false`.
  statusServices = builtins.filter (s: s.status or true) serviceList;

  # ------------------------------------------------- push status endpoints ---

  # Status-page tiles whose result is pushed from the host itself (Gatus
  # external endpoints). The `services.*.probe` schema only models active
  # probes Gatus runs from the cluster; these are questions only the machine
  # can answer (e.g. "is my egress Mullvad?"), so the host POSTs each verdict
  # and Gatus marks the tile DOWN if pushes stop arriving for `heartbeat`.
  pushStatusEndpoints = [
    {
      host = "download-vm-xps";
      group = "network";
      name = "exit-node";
      # Collector runs every 60s; 5m means ~5 missed pushes before the tile
      # flips DOWN, so a single flaky tick does not page.
      heartbeat = "5m";
    }
  ];

  # node_exporter scrape targets, one group per host.
  nodeScrapeTargets = map (h: {
    targets = [ "${tailnet.host h}:${toString nodeExporterPort}" ];
    labels = {
      host = h;
      instance = h;
    }
    // (if hosts.${h}.gpu or false then { gpu = "true"; } else { })
    // (if hosts.${h}.llm or false then { llm = "true"; } else { })
    // (if hosts.${h}.exitNode or false then { exit_node = "true"; } else { });
  }) monitoredHosts;

  # Names used as Grafana dashboard template variables and Gatus groups.
  serviceGroups =
    let
      groups = map (s: s.group) serviceList;
    in
    builtins.sort (a: b: a < b) (
      builtins.attrNames (
        builtins.listToAttrs (
          map (g: {
            name = g;
            value = true;
          }) groups
        )
      )
    );
}
